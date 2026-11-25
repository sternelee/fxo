//! Proof that the embedded ACP server runs in-process over the in-memory
//! transport: no child process, no `fx acp` spawn.
//!
//! This covers the deterministic handshake (`initialize` → `session/new`).
//! It deliberately stops before `session/prompt`: that call reaches a real
//! model over the network, which would make the suite slow and flaky. The
//! prompt path is exercised by running the app itself.
const std = @import("std");
const fx = @import("fx");
const transport_mod = @import("transport.zig");

extern "c" fn usleep(useconds: c_uint) c_int;

/// Polls the host pipe until `needle` appears or the budget runs out.
fn waitFor(
    transport: *transport_mod.Transport,
    all: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    needle: []const u8,
    budget_ms: u32,
) !bool {
    var buf: [16384]u8 = undefined;
    var waited: u32 = 0;
    while (waited < budget_ms) : (waited += 1) {
        if (std.mem.indexOf(u8, all.items, needle) != null) return true;
        _ = usleep(1_000);
        const n = transport.to_host.tryRead(&buf);
        if (n == 0) continue;
        try all.appendSlice(alloc, buf[0..n]);
    }
    return std.mem.indexOf(u8, all.items, needle) != null;
}

test "embedded fx completes the ACP handshake in-process" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var transport = transport_mod.Transport.init(alloc);
    defer transport.deinit();

    const server_thread = try std.Thread.spawn(.{}, struct {
        fn run(t: *transport_mod.Transport) void {
            fx.server.runWithTransport(std.heap.page_allocator, fx.embeddedConfig(), t.reader(), t.writer()) catch {};
        }
    }.run, .{&transport});
    // Closing the pipes is what lets the server's reader return, so join()
    // cannot block on a request that never arrives.
    defer {
        transport.close();
        server_thread.join();
    }

    var all: std.ArrayList(u8) = .empty;
    defer all.deinit(alloc);

    _ = transport.to_server.write("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":1,\"clientCapabilities\":{}}}\n");
    try std.testing.expect(try waitFor(&transport, &all, alloc, "\"protocolVersion\"", 10_000));

    // fx's ACP refuses a relative cwd, so the host must resolve one first.
    var cwd_buf: [4096]u8 = undefined;
    const cwd = std.c.getcwd(&cwd_buf, cwd_buf.len) orelse return error.NoCwd;
    const cwd_json = try std.json.Stringify.valueAlloc(alloc, std.mem.sliceTo(cwd, 0), .{});
    const new_req = try std.fmt.allocPrint(
        alloc,
        "{{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"session/new\",\"params\":{{\"cwd\":{s},\"mcpServers\":[]}}}}\n",
        .{cwd_json},
    );
    _ = transport.to_server.write(new_req);

    try std.testing.expect(try waitFor(&transport, &all, alloc, "\"sessionId\"", 10_000));
    // The session carries the config the composer's pills read.
    try std.testing.expect(std.mem.indexOf(u8, all.items, "\"configOptions\"") != null);
}

test "the embedded config resolves HOME so project instructions load" {
    // A host process never installs fx's own environment; embeddedConfig()
    // must fall back to libc's so HOME and profile paths resolve.
    const cfg = fx.embeddedConfig();
    try std.testing.expect(cfg.home_override != null);
    try std.testing.expect(cfg.home_override.?.len > 0);
    try std.testing.expect(std.Io.Dir.path.isAbsolute(cfg.home_override.?));
}

test "context notices stay out of the reply" {
    // fx sends skill-discovery and context diagnostics on the same channel as
    // the answer; the engine must drop them so the transcript reads clean.
    const engine = @import("engine.zig");
    try std.testing.expect(engine.isContextNotice("skill discovery warning: candidate \"/x\" was skipped"));
    try std.testing.expect(engine.isContextNotice("[context] skill descriptions shortened: 57"));
    try std.testing.expect(engine.isContextNotice("  skill discovery: something"));
    try std.testing.expect(!engine.isContextNotice("hello world"));
    try std.testing.expect(!engine.isContextNotice("The build is green."));
}

test "answer deltas join under one messageId and reset on a new one" {
    // fx sends the answer as incremental chunks sharing a messageId
    // ("hello" then " world"), so they must join. A new id starts over.
    const engine = @import("engine.zig");
    var snap: engine.Snapshot = .{ .alloc = std.testing.allocator };
    defer snap.deinit(std.testing.allocator);

    engine.setAgentText(&snap, "m1", "hello");
    engine.setAgentText(&snap, "m1", " world");
    try std.testing.expectEqualStrings("hello world", snap.agent_text.items);

    engine.setAgentText(&snap, "m2", "second");
    try std.testing.expectEqualStrings("second", snap.agent_text.items);
}

test "read() carries the stop reason out of the engine" {
    // A field the snapshot holds but read() forgets to copy is invisible to
    // the UI, which is how a finished turn looked like it never stopped.
    const engine_mod = @import("engine.zig");
    var engine = engine_mod.Engine.init(std.testing.allocator, "/tmp", struct {
        fn wake() void {}
    }.wake);
    defer engine.deinit();

    engine.snapshot.stop_reason = "end_turn";
    engine.snapshot.status = "idle";

    var out: engine_mod.Snapshot = .{ .alloc = std.testing.allocator };
    defer out.deinit(std.testing.allocator);
    engine.read(&out);

    try std.testing.expectEqualStrings("end_turn", out.stop_reason);
    try std.testing.expectEqualStrings("idle", out.status);
}

test "a session_info_update names the session" {
    const engine_mod = @import("engine.zig");
    var snap: engine_mod.Snapshot = .{ .alloc = std.testing.allocator };
    defer snap.deinit(std.testing.allocator);
    engine_mod.handleLineForTest(&snap,
        \\{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"session_info_update","title":"Fix the parser"}}}
    );
    try std.testing.expectEqualStrings("Fix the parser", snap.title);
    // A later title replaces it, and the old copy is freed.
    engine_mod.handleLineForTest(&snap,
        \\{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"session_info_update","title":"Fix the lexer"}}}
    );
    try std.testing.expectEqualStrings("Fix the lexer", snap.title);
}

test "read() carries the session title out of the engine" {
    const engine_mod = @import("engine.zig");
    var engine = engine_mod.Engine.init(std.testing.allocator, "/tmp", struct {
        fn wake() void {}
    }.wake);
    defer engine.deinit();
    engine.snapshot.title = "Named by fx";

    var out: engine_mod.Snapshot = .{ .alloc = std.testing.allocator };
    defer out.deinit(std.testing.allocator);
    engine.read(&out);
    try std.testing.expectEqualStrings("Named by fx", out.title);
}
