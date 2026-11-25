//! Bridge to the `fx` CLI: gathers status, usage, MCP servers, permissions and
//! doctor into a bounded snapshot on a worker thread. Settings pages read it.
const std = @import("std");

fn copyBounded(dest: []u8, src: []const u8) usize {
    const n = @min(dest.len, src.len);
    @memcpy(dest[0..n], src[0..n]);
    return n;
}

pub const Str = struct {
    buf: [128]u8 = undefined,
    len: usize = 0,
    pub fn set(s: *Str, text: []const u8) void {
        s.len = copyBounded(&s.buf, text);
    }
    pub fn slice(s: *const Str) []const u8 {
        return s.buf[0..s.len];
    }
};

pub const Server = struct {
    name: Str = .{},
    status: Str = .{},
    transport: Str = .{},
    source: Str = .{},
    tools: usize = 0,
    /// Why the server failed, when fx reports one. Shown in place of the
    /// address so the row says what is wrong.
    error_msg: Str = .{},
    /// The server's address (http url or command), shown in mono.
    address: Str = .{},
};

/// A permission mode from `fx status --json` (id, label, description).
pub const Mode = struct {
    id: Str = .{},
    name: Str = .{},
    description: Str = .{},
};

pub const ModelUse = struct {
    name: Str = .{},
    requests: f64 = 0,
    spend: f64 = 0,
};

/// A doctor check's level (design's Level).
pub const Level = enum { ok, warn, fail };

/// One `fx doctor` check: its level, name and detail.
pub const Check = struct {
    level: Level = .ok,
    name: Str = .{},
    detail: Str = .{},
};

pub const SkillItem = struct {
    name: Str = .{},
    description: Str = .{},
    /// The skill's directory, for the Open button.
    path: Str = .{},
    /// Which harness it came from: ".fx", ".agents" or ".claude".
    source: Str = .{},
};

pub const Info = struct {
    revision: u64 = 0,
    loaded: bool = false,
    // status
    auth: Str = .{},
    model: Str = .{},
    provider: Str = .{},
    permission_mode: Str = .{},
    effort: Str = .{},
    channel: Str = .{},
    build: Str = .{},
    providers: [8]Str = undefined,
    provider_count: usize = 0,
    // usage
    usage_source: Str = .{},
    usage_status: Str = .{},
    usage_reason: Str = .{},
    total_tokens: f64 = 0,
    input_tokens: f64 = 0,
    output_tokens: f64 = 0,
    cache_read_tokens: f64 = 0,
    cache_write_tokens: f64 = 0,
    reasoning_tokens: f64 = 0,
    request_count: f64 = 0,
    spend: f64 = 0,
    model_count: usize = 0,
    models: [8]ModelUse = undefined,
    model_rows: usize = 0,
    // skills (discovered from disk)
    /// Every skill found on disk; grows past any fixed cap so a machine with
    /// a hundred skills lists all of them.
    skills: std.ArrayList(SkillItem) = .empty,
    skill_count: usize = 0,
    // mcp
    servers: [8]Server = undefined,
    server_count: usize = 0,
    // model catalog (fx models --json)
    catalog: [40]Str = undefined,
    catalog_count: usize = 0,
    // permission modes (fx status --json "modes")
    modes: [4]Mode = undefined,
    mode_count: usize = 0,
    /// Grants approved in this session (fx status "session_permission_grants").
    session_grants: usize = 0,
    /// fx's profile directory and the open workspace (fx status).
    fx_home: Str = .{},
    workspace: Str = .{},
    /// Directories fx may reach as well as the primary one (fx workspace list).
    extra_dirs: [8]Str = undefined,
    extra_count: usize = 0,
    /// How many additional directories fx accepts.
    extra_limit: usize = 0,
    // permissions
    rules: [8]Str = undefined,
    rule_count: usize = 0,
    // doctor
    doctor_ok: usize = 0,
    doctor_warn: usize = 0,
    doctor_fail: usize = 0,
    /// The individual checks fx doctor reported (bounded).
    checks: [12]Check = undefined,
    check_count: usize = 0,
    doctor_version: Str = .{},

    pub fn connected(i: *const Info) bool {
        const a = i.auth.slice();
        if (a.len == 0) return false;
        var buf: [64]u8 = undefined;
        const n = @min(buf.len, a.len);
        for (a[0..n], 0..) |ch, idx| buf[idx] = std.ascii.toLower(ch);
        return std.mem.indexOf(u8, buf[0..n], "not ") == null;
    }
};

/// Friendly model label, mirroring fx-ui-main/src/app/format.rs model_name().
pub fn modelName(a: std.mem.Allocator, name: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, name, '/') == null and std.mem.indexOfScalar(u8, name, ' ') != null) {
        return a.dupe(u8, name) catch name;
    }
    const base = if (std.mem.lastIndexOfScalar(u8, name, '/')) |at| name[at + 1 ..] else name;
    var out: std.ArrayList(u8) = .empty;
    var words = std.mem.tokenizeAny(u8, base, "-_");
    var first = true;
    while (words.next()) |word| {
        if (!first) out.append(a, ' ') catch break;
        first = false;
        const upper = std.mem.eql(u8, word, "gpt") or std.mem.eql(u8, word, "glm") or
            std.mem.eql(u8, word, "ai") or std.mem.eql(u8, word, "llm") or std.mem.eql(u8, word, "oss");
        if (upper) {
            for (word) |ch| out.append(a, std.ascii.toUpper(ch)) catch break;
        } else if (word.len > 0) {
            out.append(a, std.ascii.toUpper(word[0])) catch break;
            out.appendSlice(a, word[1..]) catch break;
        }
    }
    return out.toOwnedSlice(a) catch base;
}

fn strField(obj: std.json.ObjectMap, key: []const u8) []const u8 {
    if (obj.get(key)) |v| if (v == .string) return v.string;
    return "";
}

fn numField(obj: std.json.ObjectMap, key: []const u8) f64 {
    if (obj.get(key)) |v| {
        if (v == .integer) return @floatFromInt(v.integer);
        if (v == .float) return v.float;
    }
    return 0;
}

fn parseJson(alloc: std.mem.Allocator, text: []const u8) ?std.json.Parsed(std.json.Value) {
    return std.json.parseFromSlice(std.json.Value, alloc, text, .{}) catch null;
}

/// Parses `fx status --json` into the status fields of `info`. Pure.
pub fn parseStatus(info: *Info, root: std.json.Value) void {
    if (root != .object) return;
    const o = root.object;
    info.auth.set(strField(o, "auth"));
    info.model.set(strField(o, "model"));
    info.provider.set(strField(o, "model_source"));
    info.permission_mode.set(strField(o, "permission_mode"));
    info.effort.set(strField(o, "effort"));
    info.channel.set(strField(o, "update_channel"));
    info.build.set(strField(o, "build_revision"));
    info.session_grants = @intFromFloat(numField(o, "session_permission_grants"));
    info.fx_home.set(strField(o, "fx_home"));
    info.workspace.set(strField(o, "workspace"));
    if (o.get("connected_providers")) |v| {
        if (v == .array) {
            for (v.array.items) |item| {
                if (info.provider_count >= info.providers.len) break;
                if (item == .string) {
                    info.providers[info.provider_count].set(item.string);
                    info.provider_count += 1;
                }
            }
        }
    }
    // The permission modes fx offers, with their own labels and descriptions.
    if (o.get("modes")) |v| {
        if (v == .array) {
            info.mode_count = 0;
            for (v.array.items) |item| {
                if (info.mode_count >= info.modes.len) break;
                if (item != .object) continue;
                var m = &info.modes[info.mode_count];
                m.id.set(strField(item.object, "id"));
                m.name.set(strField(item.object, "name"));
                m.description.set(strField(item.object, "description"));
                if (m.id.slice().len > 0) info.mode_count += 1;
            }
        }
    }
}

/// Parses `fx usage --period ... --json`. Pure.
pub fn parseUsage(info: *Info, root: std.json.Value) void {
    if (root != .object) return;
    const o = root.object;
    info.usage_source.set(strField(o, "source"));
    info.usage_status.set(strField(o, "status"));
    info.usage_reason.set(strField(o, "reason"));
    if (o.get("totals")) |tv| {
        if (tv == .object) {
            info.total_tokens = numField(tv.object, "total_tokens");
            info.input_tokens = numField(tv.object, "input_tokens");
            info.output_tokens = numField(tv.object, "output_tokens");
            info.cache_read_tokens = numField(tv.object, "cache_read_tokens");
            info.cache_write_tokens = numField(tv.object, "cache_write_tokens");
            info.reasoning_tokens = numField(tv.object, "reasoning_tokens");
            info.request_count = numField(tv.object, "request_count");
            info.spend = numField(tv.object, "spend");
        }
    }
    if (o.get("models")) |mv| {
        if (mv == .array) {
            info.model_count = mv.array.items.len;
            info.model_rows = 0;
            for (mv.array.items) |item| {
                if (info.model_rows >= info.models.len) break;
                if (item != .object) continue;
                var row = &info.models[info.model_rows];
                const name = strField(item.object, "model");
                row.name.set(if (name.len > 0) name else strField(item.object, "name"));
                row.requests = numField(item.object, "request_count");
                if (row.requests == 0) row.requests = numField(item.object, "requests");
                row.spend = numField(item.object, "spend");
                info.model_rows += 1;
            }
        }
    }
}

/// Parses `fx mcp list --json`. Pure.
pub fn parseMcp(info: *Info, root: std.json.Value) void {
    if (root != .object) return;
    const servers = root.object.get("servers") orelse return;
    if (servers != .array) return;
    info.server_count = 0;
    for (servers.array.items) |item| {
        if (info.server_count >= info.servers.len) break;
        if (item != .object) continue;
        var srv = &info.servers[info.server_count];
        srv.name.set(strField(item.object, "name"));
        srv.status.set(strField(item.object, "status"));
        srv.transport.set(strField(item.object, "transport"));
        srv.source.set(strField(item.object, "source"));
        info.server_count += 1;
    }
}

/// Enriches each MCP server with its tool count via `fx mcp show`.
/// Parses `fx workspace list --json` into the extra directories fx reaches.
/// Pure.
pub fn parseWorkspace(info: *Info, root: std.json.Value) void {
    info.extra_count = 0;
    if (root != .object) return;
    if (root.object.get("primary_directory")) |p| {
        if (p == .string) info.workspace.set(p.string);
    }
    if (root.object.get("limit")) |l| {
        if (l == .integer and l.integer > 0) info.extra_limit = @intCast(l.integer);
    }
    if (root.object.get("additional_directories")) |dirs| {
        if (dirs == .array) {
            for (dirs.array.items) |d| {
                if (d != .string) continue;
                if (info.extra_count >= info.extra_dirs.len) break;
                info.extra_dirs[info.extra_count].set(d.string);
                info.extra_count += 1;
            }
        }
    }
}

/// Persists an additional workspace directory for the current primary one.
/// Returns true when fx accepted it.
pub fn addWorkspaceDir(alloc: std.mem.Allocator, path: []const u8) bool {
    const out = run(alloc, &.{ "fx", "workspace", "add", path }) orelse return false;
    defer alloc.free(out);
    // fx answers with JSON when it changed something; a refusal carries an
    // error line instead.
    if (parseJson(alloc, out)) |p| {
        defer p.deinit();
        if (p.value == .object) {
            if (p.value.object.get("changed")) |ch| {
                if (ch == .bool) return ch.bool;
            }
        }
    }
    return std.mem.indexOf(u8, out, "error") == null;
}

/// Registers an MCP server by name and address (`fx mcp add NAME URL`).
/// Returns true when fx accepted it.
pub fn addMcpServer(alloc: std.mem.Allocator, name: []const u8, address: []const u8) bool {
    const out = run(alloc, &.{ "fx", "mcp", "add", name, address }) orelse return false;
    defer alloc.free(out);
    // fx prints the server it wrote on success; a refusal names the problem.
    return std.mem.indexOf(u8, out, "error") == null and
        std.mem.indexOf(u8, out, "usage:") == null;
}

pub fn loadWorkspace(alloc: std.mem.Allocator, info: *Info) void {
    if (run(alloc, &.{ "fx", "workspace", "list", "--json" })) |text| {
        defer alloc.free(text);
        if (parseJson(alloc, text)) |p| {
            defer p.deinit();
            parseWorkspace(info, p.value);
        }
    }
}

pub fn enrichMcp(alloc: std.mem.Allocator, info: *Info) void {
    for (info.servers[0..info.server_count]) |*srv| {
        const argv = [_][]const u8{ "fx", "mcp", "show", srv.name.slice(), "--json" };
        if (run(alloc, &argv)) |text| {
            defer alloc.free(text);
            if (parseJson(alloc, text)) |p| {
                defer p.deinit();
                if (p.value == .object) {
                    if (p.value.object.get("status")) |st| {
                        if (st == .string) srv.status.set(st.string);
                    }
                    if (p.value.object.get("tools")) |tl| {
                        if (tl == .array) srv.tools = tl.array.items.len;
                    }
                    if (p.value.object.get("error")) |e| {
                        if (e == .string) srv.error_msg.set(e.string);
                    }
                    if (p.value.object.get("url")) |u| {
                        if (u == .string) srv.address.set(u.string);
                    }
                    if (srv.address.slice().len == 0) {
                        if (p.value.object.get("command")) |cmd| {
                            if (cmd == .string) srv.address.set(cmd.string);
                        }
                    }
                }
            }
        }
    }
}

/// Parses `fx models --json` into the model catalog. Pure.
pub fn parseModels(info: *Info, root: std.json.Value) void {
    info.catalog_count = 0;
    if (root != .object) return;
    const ids = root.object.get("ids") orelse return;
    if (ids != .array) return;
    for (ids.array.items) |item| {
        if (item != .string) continue;
        if (info.catalog_count >= info.catalog.len) break;
        info.catalog[info.catalog_count].set(item.string);
        info.catalog_count += 1;
    }
}

/// Loads the model catalog via `fx models --json`.
pub fn loadModels(alloc: std.mem.Allocator, info: *Info) void {
    const argv = [_][]const u8{ "fx", "models", "--json" };
    const text = run(alloc, &argv) orelse return;
    defer alloc.free(text);
    if (parseJson(alloc, text)) |p| {
        defer p.deinit();
        parseModels(info, p.value);
    }
}

/// Parses `fx permissions` text output. Pure.
fn run(alloc: std.mem.Allocator, argv: []const []const u8) ?[]u8 {
    const result = std.process.run(alloc, @import("proc.zig").io(), .{ .argv = argv }) catch return null;
    alloc.free(result.stderr);
    return result.stdout;
}

/// Gathers all data synchronously from the fx CLI into `info`.
/// Discovers skills from the same roots as fx-ui-main/src/host/pickers.rs.
pub fn discoverSkills(alloc: std.mem.Allocator, info: *Info) void {
    info.skills.clearRetainingCapacity();
    const io = @import("proc.zig").io();
    const home = if (std.c.getenv("HOME")) |v| std.mem.span(v) else "";
    const bases = [_][]const u8{ ".", home };
    const harnesses = [_][]const u8{ ".fx", ".agents", ".claude" };
    info.skill_count = 0;
    for (bases) |base| {
        for (harnesses) |h| {
            const root = std.fmt.allocPrint(std.heap.c_allocator, "{s}/{s}/skills", .{ base, h }) catch continue;
            defer std.heap.c_allocator.free(root);
            var dir = std.Io.Dir.cwd().openDir(io, root, .{}) catch continue;
            defer dir.close(io);
            var it = dir.iterate();
            while (it.next(io) catch null) |entry| {
                if (entry.kind != .directory) continue;
                info.skills.append(alloc, .{}) catch break;
                const skill = &info.skills.items[info.skills.items.len - 1];
                skill.name.set(entry.name);
                skill.source.set(h);
                skill.path.set(std.fmt.allocPrint(std.heap.c_allocator, "{s}/{s}", .{ root, entry.name }) catch "");
                // Read the first description line from SKILL.md if present.
                const md_path = std.fmt.allocPrint(std.heap.c_allocator, "{s}/{s}/SKILL.md", .{ root, entry.name }) catch continue;
                defer std.heap.c_allocator.free(md_path);
                var f = std.Io.Dir.cwd().openFile(io, md_path, .{}) catch {
                    // A directory without SKILL.md is not a skill: skip it
                    // rather than listing an empty entry.
                    continue;
                };
                defer f.close(io);
                var read_buf: [512]u8 = undefined;
                var reader = f.reader(io, &read_buf);
                var content: std.ArrayList(u8) = .empty;
                defer content.deinit(std.heap.c_allocator);
                reader.interface.appendRemaining(std.heap.c_allocator, &content, .limited(4096)) catch {};
                const n = content.items.len;
                var desc: []const u8 = "";
                var lines = std.mem.splitScalar(u8, content.items[0..n], '\n');
                while (lines.next()) |line| {
                    if (!std.mem.startsWith(u8, line, "description:")) continue;
                    const rest = std.mem.trim(u8, line["description:".len..], " \t\r");
                    if (rest.len > 0 and (rest[0] == '>' or rest[0] == '|')) {
                        // A YAML folded/literal block: the text is on the
                        // following, more-indented lines. Join them into one
                        // line until the indentation ends.
                        var buf: std.ArrayList(u8) = .empty;
                        defer buf.deinit(std.heap.c_allocator);
                        while (lines.next()) |next| {
                            if (next.len == 0) continue;
                            if (next[0] != ' ' and next[0] != '\t') break;
                            const part = std.mem.trim(u8, next, " \t\r");
                            if (part.len == 0) continue;
                            if (buf.items.len > 0) buf.append(std.heap.c_allocator, ' ') catch break;
                            buf.appendSlice(std.heap.c_allocator, part) catch break;
                        }
                        desc = buf.toOwnedSlice(std.heap.c_allocator) catch "";
                    } else {
                        desc = std.mem.trim(u8, rest, " \t\r\"'");
                    }
                    break;
                }
                skill.description.set(desc);
                info.skill_count = info.skills.items.len;
            }
        }
    }
}

pub fn gather(alloc: std.mem.Allocator, info: *Info) void {
    gatherPeriod(alloc, info, "month");
}

/// Gathers fx state, reading usage for `period` (today / 7d / month).
pub fn gatherPeriod(alloc: std.mem.Allocator, info: *Info, period: []const u8) void {
    if (run(alloc, &.{ "fx", "status", "--json" })) |text| {
        defer alloc.free(text);
        if (parseJson(alloc, text)) |p| {
            defer p.deinit();
            parseStatus(info, p.value);
        }
    }
    if (run(alloc, &.{ "fx", "usage", "--period", period, "--json" })) |text| {
        defer alloc.free(text);
        if (parseJson(alloc, text)) |p| {
            defer p.deinit();
            parseUsage(info, p.value);
        }
    }
    if (run(alloc, &.{ "fx", "mcp", "list", "--json" })) |text| {
        defer alloc.free(text);
        if (parseJson(alloc, text)) |p| {
            defer p.deinit();
            parseMcp(info, p.value);
        }
    }
    if (run(alloc, &.{ "fx", "permissions" })) |text| {
        defer alloc.free(text);
        @import("fxcli_parse.zig").parsePermissions(info, text);
    }
    if (run(alloc, &.{ "fx", "doctor" })) |text| {
        defer alloc.free(text);
        @import("fxcli_parse.zig").parseDoctor(info, text);
    }
    enrichMcp(alloc, info);
    loadWorkspace(alloc, info);
    loadModels(alloc, info);
    discoverSkills(alloc, info);
    info.loaded = true;
    info.revision +%= 1;
}

const Spin = struct {
    flag: std.atomic.Value(bool) = .init(false),
    fn lock(self: *Spin) void {
        while (self.flag.swap(true, .acquire)) std.Thread.yield() catch {};
    }
    fn unlock(self: *Spin) void {
        self.flag.store(false, .release);
    }
};

/// Background loader: gathers once at start, then on each `request()`.
pub const Loader = struct {
    alloc: std.mem.Allocator,
    mutex: Spin = .{},
    info: Info = .{},
    thread: ?std.Thread = null,
    stop: std.atomic.Value(bool) = .init(false),
    pending: std.atomic.Value(bool) = .init(false),
    /// The usage period the next gather reads, so the Usage page's segments
    /// take effect on the background thread instead of blocking a frame.
    period: []const u8 = "month",
    wake: *const fn () void,

    pub fn init(alloc: std.mem.Allocator, wake: *const fn () void) Loader {
        return .{ .alloc = alloc, .wake = wake };
    }

    pub fn start(l: *Loader) void {
        l.thread = std.Thread.spawn(.{}, loop, .{l}) catch null;
    }

    pub fn deinit(l: *Loader) void {
        l.stop.store(true, .release);
        if (l.thread) |t| t.join();
    }

    pub fn request(l: *Loader) void {
        l.pending.store(true, .release);
    }

    /// Asks the background thread for a different usage period.
    pub fn setPeriod(l: *Loader, period: []const u8) void {
        l.mutex.lock();
        l.period = period;
        l.mutex.unlock();
        l.request();
    }

    pub fn read(l: *Loader, out: *Info) void {
        l.mutex.lock();
        defer l.mutex.unlock();
        out.* = l.info;
    }

    fn loop(l: *Loader) void {
        while (!l.stop.load(.acquire)) {
            l.pending.store(false, .release);
            var fresh: Info = .{};
            l.mutex.lock();
            const period = l.period;
            l.mutex.unlock();
            gatherPeriod(l.alloc, &fresh, period);
            l.mutex.lock();
            l.info = fresh;
            l.mutex.unlock();
            l.wake();
            // Wait for a refresh request, but stay responsive to stop.
            var waited: usize = 0;
            while (!l.stop.load(.acquire) and !l.pending.load(.acquire) and waited < 200) : (waited += 1) {
                std.Io.Threaded.global_single_threaded.io().sleep(std.Io.Duration.fromNanoseconds(50 * std.time.ns_per_ms), .real) catch {};
            }
        }
    }
};

test "modelName friendly-formats model ids" {
    const a = std.testing.allocator;
    const one = modelName(a, "auto/deepseek-v4.1-flash");
    defer a.free(one);
    try std.testing.expectEqualStrings("Deepseek V4.1 Flash", one);
    const two = modelName(a, "codex/gpt-6.2-sol");
    defer a.free(two);
    try std.testing.expectEqualStrings("GPT 6.2 Sol", two);
    const three = modelName(a, "Claude Sonnet 4.5");
    defer a.free(three);
    try std.testing.expectEqualStrings("Claude Sonnet 4.5", three);
}

test "parseStatus reads auth and model" {
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"auth":"configured provider","model":"auto/x","model_source":"magpie","provider_endpoint":"http://127.0.0.1:3425/v1","permission_mode":"ask","connected_providers":["a","b"],"update_channel":"stable","build_revision":"abc123"}
    , .{});
    defer parsed.deinit();
    var info: Info = .{};
    parseStatus(&info, parsed.value);
    try std.testing.expectEqualStrings("configured provider", info.auth.slice());
    try std.testing.expectEqualStrings("auto/x", info.model.slice());
    try std.testing.expect(info.connected());
    try std.testing.expectEqual(@as(usize, 2), info.provider_count);
    try std.testing.expectEqualStrings("a", info.providers[0].slice());
    try std.testing.expectEqualStrings("stable", info.channel.slice());
    // The account name comes from model_source, not the endpoint URL.
    try std.testing.expectEqualStrings("magpie", info.provider.slice());
}

test "parseUsage reads totals and status" {
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"source":"grok","status":"ok","totals":{"total_tokens":1200,"request_count":5,"spend":0.5},"models":[{"model":"g"}]}
    , .{});
    defer parsed.deinit();
    var info: Info = .{};
    parseUsage(&info, parsed.value);
    try std.testing.expectEqualStrings("grok", info.usage_source.slice());
    try std.testing.expectEqual(@as(f64, 1200), info.total_tokens);
    try std.testing.expectEqual(@as(f64, 0.5), info.spend);
    try std.testing.expectEqual(@as(usize, 1), info.model_count);
}

test "parseUsage reads the token breakdown" {
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"source":"ai_gateway","status":"ok","totals":{"total_tokens":1000,"input_tokens":600,"output_tokens":200,"cache_read_tokens":150,"cache_write_tokens":30,"reasoning_tokens":20,"request_count":3,"spend":0.1}}
    , .{});
    defer parsed.deinit();
    var info: Info = .{};
    parseUsage(&info, parsed.value);
    try std.testing.expectEqual(@as(f64, 600), info.input_tokens);
    try std.testing.expectEqual(@as(f64, 200), info.output_tokens);
    try std.testing.expectEqual(@as(f64, 150), info.cache_read_tokens);
    try std.testing.expectEqual(@as(f64, 30), info.cache_write_tokens);
    try std.testing.expectEqual(@as(f64, 20), info.reasoning_tokens);
}

test "parseMcp and permissions and doctor" {
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"servers":[{"name":"nanomcp","status":"not_started","transport":"http","source":"profile"}]}
    , .{});
    defer parsed.deinit();
    var info: Info = .{};
    parseMcp(&info, parsed.value);
    try std.testing.expectEqual(@as(usize, 1), info.server_count);
    try std.testing.expectEqualStrings("nanomcp", info.servers[0].name.slice());

    @import("fxcli_parse.zig").parsePermissions(&info, "[permissions] mode=ask\n[permissions] configured rules:\n[permissions] shell: git status\n");
    try std.testing.expectEqual(@as(usize, 1), info.rule_count);
    try std.testing.expectEqualStrings("git status", info.rules[0].slice());

    @import("fxcli_parse.zig").parseDoctor(&info, "[doctor] version=0.0.17\n[ok] git: fine\n[warn] skills: skipped\n[fail] auth: missing\n");
    try std.testing.expectEqualStrings("0.0.17", info.doctor_version.slice());
    try std.testing.expectEqual(@as(usize, 1), info.doctor_ok);
    try std.testing.expectEqual(@as(usize, 1), info.doctor_warn);
    try std.testing.expectEqual(@as(usize, 1), info.doctor_fail);
}
