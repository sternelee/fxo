//! ACP engine: owns the `fx acp` child process on a worker thread.
//! Speaks JSON-RPC 2.0 over stdio. The UI thread reads a bounded snapshot.
const std = @import("std");

const parse = @import("acp_parse.zig");
const copyBounded = parse.copyBounded;
pub const PermOption = parse.PermOption;
pub const Permission = parse.Permission;
pub const ToolStep = parse.ToolStep;

pub const Snapshot = struct {
    /// The allocator every buffer here grows with; set by Engine.init.
    alloc: std.mem.Allocator,
    revision: u64 = 0,
    connected: bool = false,
    err_msg: ?[]const u8 = null,
    session_id: ?[]const u8 = null,
    agent_text: std.ArrayList(u8) = .empty,
    /// The messageId the current agent_text belongs to. fx sends the whole
    /// answer so far on every chunk for a message, so a new chunk with the
    /// same id replaces the text instead of appending to it.
    agent_message_id: [64]u8 = undefined,
    agent_message_len: usize = 0,
    thought_text: std.ArrayList(u8) = .empty,
    /// The session's name as fx reported it (session_info_update). Points at
    /// title_owned, which the snapshot frees.
    title: []const u8 = "",
    title_owned: ?[]u8 = null,
    status: []const u8 = "idle",
    /// The ACP stopReason from the last session/prompt (end_turn, cancelled,
    /// max_tokens, …). Empty until the first prompt finishes.
    stop_reason: []const u8 = "",
    permission: ?Permission = null,
    steps: [32]ToolStep = undefined,
    step_count: usize = 0,

    pub fn deinit(s: *Snapshot, alloc: std.mem.Allocator) void {
        _ = alloc;
        s.agent_text.deinit(s.alloc);
        s.thought_text.deinit(s.alloc);
        if (s.title_owned) |t| s.alloc.free(t);
        s.title_owned = null;
        s.title = "";
    }
    pub fn findStep(s: *Snapshot, id: []const u8) ?*ToolStep {
        for (s.steps[0..s.step_count]) |*step| {
            if (std.mem.eql(u8, step.idSlice(), id)) return step;
        }
        return null;
    }
    pub fn addStep(s: *Snapshot) ?*ToolStep {
        if (s.step_count >= s.steps.len) return null;
        const step = &s.steps[s.step_count];
        step.* = .{};
        s.step_count += 1;
        return step;
    }
};

const Spin = struct {
    flag: std.atomic.Value(bool) = .init(false),
    fn lock(self: *Spin) void {
        while (self.flag.swap(true, .acquire)) std.Thread.yield() catch {};
    }
    fn unlock(self: *Spin) void {
        self.flag.store(false, .release);
    }
};

pub const Engine = struct {
    alloc: std.mem.Allocator,
    mutex: Spin = .{},
    snapshot: Snapshot,
    wake: *const fn () void,
    thread: ?std.Thread = null,
    stop: std.atomic.Value(bool) = .init(false),
    queue: std.ArrayList([]const u8) = .empty,
    queue_mutex: Spin = .{},
    cwd: []const u8,
    /// The in-memory transport the embedded server talks over. Set while the
    /// worker runs; writes from the UI go through it.
    transport: ?*@import("transport.zig").Transport = null,
    /// Serializes writes from the UI thread into the transport.
    write_mutex: Spin = .{},
    /// Shared request id counter, bumped under write_mutex. The handshake
    /// uses ids 1 (initialize) and 2 (session/new), so outbound requests start
    /// at 3; reusing an id makes a reply look like it belongs to another call.
    next_id: u64 = 3,

    pub fn init(alloc: std.mem.Allocator, cwd: []const u8, wake: *const fn () void) Engine {
        return .{
            .alloc = alloc,
            .cwd = alloc.dupe(u8, cwd) catch ".",
            .wake = wake,
            .snapshot = .{ .alloc = alloc },
        };
    }

    pub fn start(e: *Engine) void {
        e.thread = std.Thread.spawn(.{}, run, .{e}) catch null;
    }

    pub fn deinit(e: *Engine) void {
        e.stop.store(true, .release);
        if (e.thread) |t| t.join();
        e.snapshot.deinit(e.alloc);
        e.alloc.free(e.cwd);
        e.queue_mutex.lock();
        for (e.queue.items) |q| e.alloc.free(q);
        e.queue.deinit(e.alloc);
        e.queue_mutex.unlock();
    }

    pub fn send(e: *Engine, text: []const u8, session_id: ?[]const u8) void {
        _ = session_id;
        const copy = e.alloc.dupe(u8, text) catch return;
        e.queue_mutex.lock();
        e.queue.append(e.alloc, copy) catch e.alloc.free(copy);
        e.queue_mutex.unlock();
        // Nothing else will wake the worker: a prompt must go out now, not
        // wait for the next inbound message to drain the queue.
        drainQueueImpl(e);
    }

    /// Cancels the running turn through ACP `session/cancel`.
    pub fn cancel(e: *Engine) void {
        e.write_mutex.lock();
        defer e.write_mutex.unlock();
        const t = e.transport orelse return;
        const sid = e.snapshot.session_id orelse return;
        const sid_json = std.json.Stringify.valueAlloc(e.alloc, sid, .{}) catch return;
        defer e.alloc.free(sid_json);
        const req = std.fmt.allocPrint(e.alloc, "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"session/cancel\",\"params\":{{\"sessionId\":{s}}}}}", .{ e.next_id, sid_json }) catch return;
        defer e.alloc.free(req);
        e.next_id += 1;
        writeFrame(t, req);
    }

    /// Answers a pending ACP permission request. `option_id == null` cancels.
    pub fn answer(e: *Engine, request_id: i64, option_id: ?[]const u8) void {
        e.write_mutex.lock();
        defer e.write_mutex.unlock();
        const t = e.transport orelse return;
        const reply = if (option_id) |oid|
            std.fmt.allocPrint(e.alloc, "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"result\":{{\"outcome\":{{\"outcome\":\"selected\",\"optionId\":\"{s}\"}}}}}}", .{ request_id, oid }) catch return
        else
            std.fmt.allocPrint(e.alloc, "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"result\":{{\"outcome\":{{\"outcome\":\"cancelled\"}}}}}}", .{request_id}) catch return;
        defer e.alloc.free(reply);
        writeFrame(t, reply);
    }

    /// Sends `session/set_config_option` (mode/model/effort/fast) to the live
    /// session. The reply updates the snapshot's session_id path; failures are
    /// reported through the snapshot's error field.
    pub fn setConfigOption(e: *Engine, config_id: []const u8, value: []const u8) void {
        e.write_mutex.lock();
        defer e.write_mutex.unlock();
        const t = e.transport orelse return;
        const sid = e.snapshot.session_id orelse return;
        const sid_json = std.json.Stringify.valueAlloc(e.alloc, sid, .{}) catch return;
        defer e.alloc.free(sid_json);
        const id_json = std.json.Stringify.valueAlloc(e.alloc, config_id, .{}) catch return;
        defer e.alloc.free(id_json);
        const val_json = std.json.Stringify.valueAlloc(e.alloc, value, .{}) catch return;
        defer e.alloc.free(val_json);
        const req = std.fmt.allocPrint(e.alloc, "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"session/set_config_option\",\"params\":{{\"sessionId\":{s},\"configId\":{s},\"value\":{s}}}}}", .{ e.next_id, sid_json, id_json, val_json }) catch return;
        defer e.alloc.free(req);
        e.next_id += 1;
        writeFrame(t, req);
    }

    pub fn clearPermission(e: *Engine) void {
        e.mutex.lock();
        e.snapshot.permission = null;
        e.snapshot.status = "working";
        e.snapshot.revision +%= 1;
        e.mutex.unlock();
        e.wake();
    }

    pub fn read(e: *Engine, out: *Snapshot) void {
        e.mutex.lock();
        defer e.mutex.unlock();
        out.revision = e.snapshot.revision;
        out.connected = e.snapshot.connected;
        out.err_msg = e.snapshot.err_msg;
        out.session_id = e.snapshot.session_id;
        out.status = e.snapshot.status;
        out.stop_reason = e.snapshot.stop_reason;
        out.title = e.snapshot.title;
        out.permission = e.snapshot.permission;
        out.steps = e.snapshot.steps;
        out.step_count = e.snapshot.step_count;
        out.agent_text.clearRetainingCapacity();
        out.agent_text.appendSlice(e.alloc, e.snapshot.agent_text.items) catch {};
        out.thought_text.clearRetainingCapacity();
        out.thought_text.appendSlice(e.alloc, e.snapshot.thought_text.items) catch {};
    }

    fn publish(e: *Engine, mutate: *const fn (*Snapshot, []const u8) void, data: []const u8) void {
        e.mutex.lock();
        defer e.mutex.unlock();
        mutate(&e.snapshot, data);
        e.snapshot.revision +%= 1;
        e.wake();
    }
};

fn setConnected(s: *Snapshot, _: []const u8) void {
    s.connected = true;
    s.err_msg = null;
    s.status = "ready";
}

fn setError(s: *Snapshot, msg: []const u8) void {
    s.err_msg = msg;
    s.connected = false;
    s.status = "error";
}

fn setWorking(s: *Snapshot, _: []const u8) void {
    s.agent_text.clearRetainingCapacity();
    s.status = "working";
}

/// fx reports context diagnostics (skill discovery, shortened descriptions,
/// omitted instructions) on the same channel as the answer. They belong in a
/// notice list, not in the reply, so the transcript stays readable.
pub fn isContextNotice(text: []const u8) bool {
    const prefixes = [_][]const u8{
        "skill discovery warning:",
        "[context]",
        "skill discovery:",
    };
    const trimmed = std.mem.trimStart(u8, text, " \t\r\n");
    for (prefixes) |p| {
        if (std.mem.startsWith(u8, trimmed, p)) return true;
    }
    return false;
}

/// Appends one answer delta. fx sends the answer as incremental chunks that
/// share a messageId ("hello" then " world"), so the same id appends and a new
/// id starts a fresh answer.
pub fn setAgentText(s: *Snapshot, message_id: []const u8, text: []const u8) void {
    const same = s.agent_message_len == message_id.len and
        std.mem.eql(u8, s.agent_message_id[0..s.agent_message_len], message_id);
    if (!same) {
        if (message_id.len <= s.agent_message_id.len) {
            @memcpy(s.agent_message_id[0..message_id.len], message_id);
            s.agent_message_len = message_id.len;
        } else {
            s.agent_message_len = 0;
        }
        s.agent_text.clearRetainingCapacity();
    }
    s.agent_text.appendSlice(s.alloc, text) catch {};
}

fn appendThought(s: *Snapshot, text: []const u8) void {
    s.thought_text.appendSlice(s.alloc, text) catch {};
}

fn setIdle(s: *Snapshot, _: []const u8) void {
    s.status = "idle";
}

const IO = std.Io;

/// Runs fx's ACP server in this process over an in-memory transport, the way
/// the CLI runs it, instead of spawning `fx acp` as a child. The server owns
/// the read loop; this thread drains what it writes back.
fn run(e: *Engine) void {
    var transport = @import("transport.zig").Transport.init(e.alloc);
    defer transport.deinit();

    e.transport = &transport;
    defer e.transport = null;

    // The server blocks on its reader, so it runs on its own thread while this
    // one consumes replies.
    const server_thread = std.Thread.spawn(.{}, serveFx, .{ e, &transport }) catch |err| {
        const msg = std.fmt.allocPrint(e.alloc, "could not start fx: {s}", .{@errorName(err)}) catch "could not start fx";
        e.publish(setError, msg);
        return;
    };

    // Ask for a session as soon as the server is up.
    writeFrame(&transport, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":1,\"clientCapabilities\":{}}}");

    var line_buf: std.ArrayList(u8) = .empty;
    defer line_buf.deinit(e.alloc);
    var session_requested = false;
    var chunk: [8192]u8 = undefined;
    while (!e.stop.load(.acquire)) {
        const n = transport.to_host.read(&chunk);
        if (n == 0) break;
        for (chunk[0..n]) |byte| {
            if (byte != '\n') {
                line_buf.append(e.alloc, byte) catch continue;
                continue;
            }
            if (line_buf.items.len > 1) {
                handleLine(e, line_buf.items);
                // The initialize reply is the cue to open a session, the same
                // handshake the CLI performs.
                if (!session_requested and sawInitializeResult(line_buf.items)) {
                    session_requested = true;
                    requestSession(e, &transport);
                }
            }
            line_buf.clearRetainingCapacity();
        }
    }
    transport.close();
    server_thread.join();
}

/// Opens a session in the workspace this engine was built for.
fn requestSession(e: *Engine, transport: *@import("transport.zig").Transport) void {
    const cwd_json = std.json.Stringify.valueAlloc(e.alloc, e.cwd, .{}) catch return;
    defer e.alloc.free(cwd_json);
    const req = std.fmt.allocPrint(e.alloc, "{{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"session/new\",\"params\":{{\"cwd\":{s},\"mcpServers\":[]}}}}", .{cwd_json}) catch return;
    defer e.alloc.free(req);
    writeFrame(transport, req);
}

/// Runs the embedded ACP server until the transport closes.
fn serveFx(e: *Engine, transport: *@import("transport.zig").Transport) void {
    const fx = @import("fx");
    fx.server.runWithTransport(e.alloc, fx.embeddedConfig(), transport.reader(), transport.writer()) catch |err| {
        if (e.stop.load(.acquire)) return;
        const msg = std.fmt.allocPrint(e.alloc, "fx server stopped: {s}", .{@errorName(err)}) catch "fx server stopped";
        e.publish(setError, msg);
    };
}

fn sawInitializeResult(line: []const u8) bool {
    return std.mem.indexOf(u8, line, "\"agentInfo\"") != null or
        std.mem.indexOf(u8, line, "\"protocolVersion\"") != null;
}

/// Writes one newline-terminated JSON-RPC frame into the transport.
fn writeFrame(t: *@import("transport.zig").Transport, text: []const u8) void {
    if (!t.to_server.write(text)) return;
    _ = t.to_server.write("\n");
}

/// Test seam: applies one inbound frame to a bare snapshot, so a probe can
/// exercise the real chunk handling without an Engine.
pub fn handleLineForTest(snap: *Snapshot, line: []const u8) void {
    var parsed = std.json.parseFromSlice(std.json.Value, snap.alloc, line, .{}) catch return;
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return;
    const obj = root.object;
    const method = obj.get("method") orelse return;
    if (method != .string or !std.mem.eql(u8, method.string, "session/update")) return;
    const params = obj.get("params") orelse return;
    if (params != .object) return;
    const update = params.object.get("update") orelse return;
    if (update != .object) return;
    const kind = update.object.get("sessionUpdate") orelse return;
    if (kind != .string) return;
    if (std.mem.eql(u8, kind.string, "agent_message_chunk")) {
        const content = update.object.get("content") orelse return;
        if (content != .object) return;
        const txt = content.object.get("text") orelse return;
        if (txt != .string or isContextNotice(txt.string)) return;
        const mid = update.object.get("messageId");
        const message_id: []const u8 = if (mid != null and mid.? == .string) mid.?.string else "";
        setAgentText(snap, message_id, txt.string);
        return;
    }
    // fx names the session once it knows what the turn is about; the sidebar
    // and the header show that name instead of "New session".
    if (std.mem.eql(u8, kind.string, "session_info_update")) {
        const ttl = update.object.get("title") orelse return;
        if (ttl != .string or ttl.string.len == 0) return;
        const owned = snap.alloc.dupe(u8, ttl.string) catch return;
        if (snap.title_owned) |old| snap.alloc.free(old);
        snap.title_owned = owned;
        snap.title = owned;
        snap.revision +%= 1;
        return;
    }
}

fn handleLine(e: *Engine, line: []const u8) void {
    var parsed = std.json.parseFromSlice(std.json.Value, e.alloc, line, .{}) catch return;
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return;
    const obj = root.object;

    if (obj.get("id")) |id_val| {
        if (id_val != .integer) return;
        const result = obj.get("result") orelse {
            // Surface fx's own message: "acp request failed" alone hides the
            // cause (a bad cwd, a missing session store, a refused prompt).
            if (obj.get("error")) |err| {
                const msg = if (err == .object)
                    (if (err.object.get("message")) |m|
                        (if (m == .string) m.string else "acp request failed")
                    else
                        "acp request failed")
                else
                    "acp request failed";
                e.publish(setError, msg);
            }
            return;
        };
        if (result == .object) {
            if (result.object.get("sessionId")) |sid| {
                if (sid == .string) {
                    e.mutex.lock();
                    e.snapshot.session_id = e.alloc.dupe(u8, sid.string) catch null;
                    e.mutex.unlock();
                    e.publish(setConnected, "");
                }
            }
            // session/prompt answers with a stopReason: end_turn, cancelled,
            // max_tokens, refusal, or similar. Record it so the turn can say
            // why it stopped.
            if (result.object.get("stopReason")) |reason| {
                if (reason == .string) {
                    // The slice points into the parsed frame, which is freed
                    // when this handler returns; copy it so the turn can read
                    // the reason later.
                    const owned = e.alloc.dupe(u8, reason.string) catch "";
                    e.mutex.lock();
                    e.snapshot.stop_reason = owned;
                    e.snapshot.status = "idle";
                    e.snapshot.revision +%= 1;
                    e.mutex.unlock();
                    e.wake();
                }
            }
        }
        return;
    }

    const method = obj.get("method") orelse return;
    if (method != .string) return;

    if (std.mem.eql(u8, method.string, "session/request_permission")) {
        // Publish the request; the UI answers it through Engine.answer().
        const perm = parse.parsePermission(obj);
        e.mutex.lock();
        e.snapshot.permission = perm;
        e.snapshot.status = "waiting";
        e.snapshot.revision +%= 1;
        e.mutex.unlock();
        e.wake();
        return;
    }

    if (!std.mem.eql(u8, method.string, "session/update")) return;
    const params = obj.get("params") orelse return;
    if (params != .object) return;
    const update = params.object.get("update") orelse return;
    if (update != .object) return;
    const kind = update.object.get("sessionUpdate") orelse return;
    if (kind != .string) return;

    if (std.mem.eql(u8, kind.string, "agent_message_chunk")) {
        const content = update.object.get("content") orelse return;
        if (content != .object) return;
        const txt = content.object.get("text") orelse return;
        if (txt != .string or isContextNotice(txt.string)) return;
        const mid = update.object.get("messageId");
        const message_id: []const u8 = if (mid != null and mid.? == .string) mid.?.string else "";
        e.mutex.lock();
        setAgentText(&e.snapshot, message_id, txt.string);
        e.snapshot.revision +%= 1;
        e.mutex.unlock();
        e.wake();
    } else if (std.mem.eql(u8, kind.string, "agent_thought_chunk")) {
        const content = update.object.get("content") orelse return;
        if (content == .object) {
            if (content.object.get("text")) |txt| {
                if (txt == .string) e.publish(appendThought, txt.string);
            }
        }
    } else if (std.mem.eql(u8, kind.string, "tool_call")) {
        e.mutex.lock();
        if (e.snapshot.addStep()) |step| parse.applyToolCall(step, update.object);
        e.snapshot.revision +%= 1;
        e.mutex.unlock();
        e.wake();
    } else if (std.mem.eql(u8, kind.string, "tool_call_update")) {
        e.mutex.lock();
        parse.applyToolUpdate(&e.snapshot.steps, e.snapshot.step_count, update.object);
        e.snapshot.revision +%= 1;
        e.mutex.unlock();
        e.wake();
    } else if (std.mem.eql(u8, kind.string, "prompt_complete")) {
        e.publish(setIdle, "");
    }

    drainQueueImpl(e);
}

/// Sends the next queued prompt once a session exists.
fn drainQueueImpl(e: *Engine) void {
    e.mutex.lock();
    const sid = e.snapshot.session_id;
    e.mutex.unlock();
    if (sid == null) return;
    e.queue_mutex.lock();
    if (e.queue.items.len == 0) {
        e.queue_mutex.unlock();
        return;
    }
    const text = e.queue.orderedRemove(0);
    e.queue_mutex.unlock();
    defer e.alloc.free(text);
    const t = e.transport orelse return;
    e.publish(setWorking, "");
    const escaped = std.json.Stringify.valueAlloc(e.alloc, text, .{}) catch return;
    defer e.alloc.free(escaped);
    const sid_json = std.json.Stringify.valueAlloc(e.alloc, sid.?, .{}) catch return;
    defer e.alloc.free(sid_json);
    const req = std.fmt.allocPrint(e.alloc, "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"session/prompt\",\"params\":{{\"sessionId\":{s},\"prompt\":[{{\"type\":\"text\",\"text\":{s}}}]}}}}", .{ e.next_id, sid_json, escaped }) catch return;
    defer e.alloc.free(req);
    e.next_id += 1;
    writeFrame(t, req);
}

test "permission parses tool call and options" {
    const line =
        \\{"jsonrpc":"2.0","id":9,"method":"session/request_permission","params":{"sessionId":"s1","toolCall":{"toolCallId":"c9","name":"shell","title":"shell.run echo hi","kind":"execute","status":"pending","rawInput":{"action":"run","command":"echo hi"}},"options":[{"optionId":"allow_once","name":"Allow once","kind":"allow_once"},{"optionId":"allow_always","name":"Allow for this session","kind":"allow_always"},{"optionId":"reject_once","name":"Reject","kind":"reject_once"}]}}
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, line, .{});
    defer parsed.deinit();
    const p = parse.parsePermission(parsed.value.object);
    try std.testing.expectEqual(@as(i64, 9), p.request_id);
    try std.testing.expect(p.isExecute());
    try std.testing.expectEqualStrings("Run this command?", p.questionSlice());
    try std.testing.expectEqualStrings("echo hi", p.detailSlice());
    try std.testing.expectEqual(@as(usize, 3), p.option_count);
    try std.testing.expectEqualStrings("allow_once", p.defaultAllow().?.idSlice());
    try std.testing.expect(p.byKind("reject_once") != null);
}

test "tool call and update parse into a step" {
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"sessionUpdate":"tool_call","toolCallId":"c1","name":"shell","title":"Running shell","kind":"execute","status":"pending","rawInput":{"command":"echo hi"}}
    , .{});
    defer parsed.deinit();
    var snap: Snapshot = .{ .alloc = std.testing.allocator };
    defer snap.deinit(std.testing.allocator);
    const step = snap.addStep().?;
    parse.applyToolCall(step, parsed.value.object);
    try std.testing.expectEqualStrings("c1", step.idSlice());
    try std.testing.expectEqualStrings("execute", step.kindSlice());
    try std.testing.expectEqualStrings("echo hi", step.detailSlice());
    try std.testing.expect(step.isLive());

    var upd = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"sessionUpdate":"tool_call_update","toolCallId":"c1","status":"completed","content":[{"type":"content","content":{"type":"text","text":"hi\n"}}]}
    , .{});
    defer upd.deinit();
    parse.applyToolUpdate(&snap.steps, snap.step_count, upd.value.object);
    try std.testing.expectEqualStrings("completed", snap.steps[0].statusSlice());
    try std.testing.expectEqualStrings("hi\n", snap.steps[0].outputSlice());
    try std.testing.expect(!snap.steps[0].isLive());
}

test "snapshot defaults" {
    const s: Snapshot = .{ .alloc = std.testing.allocator };
    try std.testing.expect(!s.connected);
    try std.testing.expectEqualStrings("idle", s.status);
    try std.testing.expect(s.permission == null);
    try std.testing.expectEqual(@as(usize, 0), s.step_count);
}
