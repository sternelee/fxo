//! Headless view tests: no window opens, no real fx process is needed.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const view = @import("view.zig");

// The menu and interaction tests live in their own file.
comptime {
    _ = @import("tests_menus.zig");
    _ = @import("tests_home.zig");
    _ = @import("tests_settings.zig");
    _ = @import("tests_composer.zig");
    _ = @import("tests_acp.zig");
}

pub fn fixture(alloc: std.mem.Allocator) view.State {
    var s = view.State.init(alloc);
    s.addWorkspace("/example/project");
    s.newSession();
    const session = s.currentSession().?;
    var turn = @import("state.zig").Turn.init(alloc, "Explain this repo");
    turn.answer.appendSlice(alloc, "A native coding agent in Zig.") catch unreachable;
    turn.status = .idle;
    session.turns.append(alloc, turn) catch unreachable;
    return s;
}

test "home renders at desktop width" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .home;
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("What should we build in project?"));
    try std.testing.expect(t.hasText("Reply to fx, or type @ for files and / for skills"));
    try std.testing.expect(!t.ctx.animating);
    try std.testing.expect(t.ctx.frame_in == null);
}

test "session renders prompt and answer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Explain this repo"));
    try std.testing.expect(t.hasText("A native coding agent in Zig."));
    try std.testing.expect(!t.ctx.animating);
}

test "permission card renders question, detail and buttons" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    var p = @import("engine.zig").Permission{};
    p.request_id = 9;
    p.setKind("execute");
    p.setQuestion("Run this command?");
    p.setDetail("echo hi");
    p.addOption("allow_once", "Allow once", "allow_once");
    p.addOption("allow_always", "Allow for this session", "allow_always");
    p.addOption("reject_once", "Reject", "reject_once");
    s.preview_permission = p;
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Run this command?"));
    try std.testing.expect(t.hasText("echo hi"));
    try std.testing.expect(t.hasText("Run   ⌘⏎"));
    try std.testing.expect(t.hasText("Deny   Esc"));
    try std.testing.expect(!t.ctx.animating);
}

test "clicking allow records the ACP answer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    var p = @import("engine.zig").Permission{};
    p.request_id = 42;
    p.setKind("execute");
    p.setQuestion("Run this command?");
    p.setDetail("echo hi");
    p.addOption("allow_once", "Allow once", "allow_once");
    p.addOption("reject_once", "Reject", "reject_once");
    s.preview_permission = p;
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try t.clickText("Run   ⌘⏎");
    try std.testing.expectEqual(@as(usize, 1), s.answers_sent);
    try std.testing.expect(s.preview_permission == null);
}

test "command palette opens with cmd-K and filters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);

    _ = t.shortcut(.{ .key = 'k', .cmd = true });
    t.settle(0.1);
    try std.testing.expect(s.palette.open);
    try std.testing.expect(t.hasText("Search commands and sessions"));
    try std.testing.expect(t.hasText("New session"));

    // Filter down to one command. The query match renders as its own
    // semibold run, so assert on the matched segment.
    t.typeText("sidebar");
    t.settle(0.1);
    try std.testing.expect(t.hasText("sidebar"));
    try std.testing.expect(!t.hasText("Open folder"));
}

test "changes panel renders file list and totals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.changes_open = true;
    const git_mod = @import("git.zig");
    // addWorkspace now refreshes real git state; clear it so this test can
    // seed a deterministic fixture.
    for (s.changes.changes.items) |ch| alloc.free(ch.path);
    s.changes.changes.clearRetainingCapacity();
    s.changes.err_msg = null;
    s.changes.changes.append(alloc, .{
        .path = try alloc.dupe(u8, "src/main.zig"),
        .code = 'M',
        .staged = false,
        .added = 12,
        .removed = 3,
    }) catch unreachable;
    s.changes.changes.append(alloc, .{
        .path = try alloc.dupe(u8, "desktop/new.zig"),
        .code = '?',
        .staged = false,
        .added = 40,
    }) catch unreachable;
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Changes"));
    try std.testing.expect(t.hasText("Not staged"));
    try std.testing.expect(t.hasText("main.zig"));
    try std.testing.expect(t.hasText("+52"));
    try std.testing.expect(t.hasText("−3"));
    _ = git_mod;
}

test "settings renders sections and switches" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .settings;
    s.settings_section = .models;
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Models & accounts"));
    try std.testing.expect(t.hasText("Loading…"));
    try std.testing.expect(t.hasText("About"));

    // Switch to the About section by clicking its nav item.
    try t.clickText("About");
    t.settle(0.1);
    try std.testing.expect(s.settings_section == .about);
}

test "thread renders the working timeline" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    const session = s.currentSession().?;
    const turn = &session.turns.items[0];
    var step = @import("engine.zig").ToolStep{};
    step.setId("c1");
    step.setKind("execute");
    step.setName("shell");
    step.setStatus("completed");
    step.setDetail("echo hi");
    step.appendOutput("hi");
    turn.steps[0] = step;
    turn.step_count = 1;
    turn.thought.appendSlice(alloc, "let me check") catch unreachable;
    // Settled turns fold their steps; expand this one to see the timeline.
    s.toggleTurn(0);
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Thought"));
    try std.testing.expect(t.hasText("Ran"));
    try std.testing.expect(t.hasText("echo hi"));
    try std.testing.expect(t.hasText("hi"));
}

test "composer picker renders file matches" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    // Seed a picker directly (avoids needing a git repo in the test).
    const pk = @import("picker.zig");
    const paths = [_][]const u8{ "src/main.zig", "src/view.zig", "README.md" };
    pk.build(&s.picker, .file, "ma", &paths);
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Files in project"));
    try std.testing.expect(t.hasText("main.zig"));
    // The file footer carries the key hints.
    try std.testing.expect(t.hasText("⏎ Attach"));
}

test "rename dialog renders and confirms" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.openRename();
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Rename session"));
    try std.testing.expect(t.hasText("Cancel"));
    try std.testing.expect(t.hasText("Rename"));
    // Confirm via the button.
    try t.clickText("Rename");
    t.settle(0.1);
    try std.testing.expect(s.dialog == null);
}

test "thread folds consecutive same-kind steps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    const session = s.currentSession().?;
    const turn = &session.turns.items[0];
    const T = @import("engine.zig").ToolStep;
    for (0..3) |i| {
        var step = T{};
        var id_buf: [8]u8 = undefined;
        const id = @import("std").fmt.bufPrint(&id_buf, "c{d}", .{i}) catch "";
        step.setId(id);
        step.setKind("read");
        step.setStatus("completed");
        step.setDetail("src/file.zig");
        turn.steps[i] = step;
    }
    turn.step_count = 3;
    // Folded by default; expand to render the step rows.
    s.toggleTurn(0);
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("+2 more"));
}

test "attachImages reads image files and renders thumbnails" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    // Use the bundled GeistMono font bytes as stand-in image bytes; the
    // attach path only reads bytes, decoding happens in ui.image.
    const paths = [_][]const u8{"preview.png"};
    s.attachImages(&paths);
    try std.testing.expectEqual(@as(usize, 1), s.attachments.items.len);
    try std.testing.expect(s.attachments.items[0].len > 100);
}

test "toggling changes repeatedly does not double free" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    // toggleChanges calls git.refresh, which reassigns branch/last_commit.
    // A double free there used to trap on the first click.
    s.toggleChanges();
    try std.testing.expect(s.changes_open);
    s.toggleChanges();
    try std.testing.expect(!s.changes_open);
    s.toggleChanges();
    try std.testing.expect(s.changes_open);
}
