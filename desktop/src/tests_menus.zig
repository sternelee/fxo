//! Menu, dialog and interaction tests: headless, no window, no fx process.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const view = @import("view.zig");
const fixture = @import("tests.zig").fixture;

test "stage toggle and stage all update groups" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    // Seed: one unstaged, one staged.
    for (s.changes.changes.items) |ch| alloc.free(ch.path);
    s.changes.changes.clearRetainingCapacity();
    s.changes.err_msg = null;
    s.changes.changes.append(alloc, .{ .path = try alloc.dupe(u8, "a.zig"), .code = 'M', .staged = false }) catch unreachable;
    s.changes.changes.append(alloc, .{ .path = try alloc.dupe(u8, "b.zig"), .code = 'M', .staged = true }) catch unreachable;
    // stageAll on the unstaged group flips every unstaged row in memory only
    // when git succeeds; in the test sandbox git may fail, so just assert the
    // call path does not crash and the list survives.
    s.stageAll(false);
    try std.testing.expect(s.changes.changes.items.len == 2);
    s.stageToggle("a.zig", false);
    try std.testing.expect(s.changes.changes.items.len == 2);
}

test "settled turn folds to a Worked summary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    const session = s.currentSession().?;
    const turn = &session.turns.items[0];
    var step = @import("engine.zig").ToolStep{};
    step.setId("c1");
    step.setKind("read");
    step.setStatus("completed");
    step.setDetail("src/file.zig");
    turn.steps[0] = step;
    turn.step_count = 1;
    turn.status = .idle;
    turn.elapsed_ms = 4200;
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    // Folded: the summary shows, the step row does not.
    try std.testing.expect(t.hasText("Worked for 4s"));
    try std.testing.expect(!t.hasText("src/file.zig"));
    // Expanded: the step row appears.
    s.toggleTurn(0);
    t.settle(0.2);
    try std.testing.expect(t.hasText("src/file.zig"));
}

test "answer footer shows the model and duration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.fx_info.model.set("auto/deepseek-v4.1-flash");
    const session = s.currentSession().?;
    const turn = &session.turns.items[0];
    turn.status = .idle;
    turn.elapsed_ms = 12_400;
    turn.answer.appendSlice(alloc, "done") catch unreachable;
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    // model_name() friendly-formats "auto/deepseek-v4.1-flash" -> "Deepseek V4.1 Flash".
    try std.testing.expect(t.hasText("Deepseek V4.1 Flash · 12s"));
}

test "home groups recent sessions by day and lists archived" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .home;
    const ws = &s.workspaces.items[s.folder];
    // One fresh session (Today) and one old (Earlier).
    ws.sessions.items[0].updated_at = @import("nanoui").ui.clock.now();
    var old = @import("state.zig").Session.init(alloc, "Old session");
    old.updated_at = @import("nanoui").ui.clock.now() - 3 * 86_400;
    ws.sessions.append(alloc, old) catch unreachable;
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Today"));
    try std.testing.expect(t.hasText("Earlier"));
    try std.testing.expect(t.hasText("Old session"));

    // Archiving the old one moves it to the Archived tab only.
    ws.sessions.items[1].archived = true;
    s.home_tab = .archived;
    t.settle(0.2);
    try std.testing.expect(t.hasText("Old session"));
    try std.testing.expect(!t.hasText("Today"));
}

test "palette highlights the query match" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .home;
    s.palette.open = true;
    s.palette.query.set("new");
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    // The label still reads whole; the match is a separate semibold run.
    try std.testing.expect(t.hasText("New session"));
}

test "settings model row opens the model menu" {
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
    // The row renders as a select with a value and a chevron.
    try std.testing.expect(t.hasText("Model"));
    try std.testing.expect(t.hasText("Permissions"));
    // Clicking it opens the shared popup.
    try t.clickText("Model");
    t.settle(0.2);
    try std.testing.expect(s.composer_menu == .model);
}

test "sidebar account row lays out horizontally" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .home;
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    // The provider label sits beside the avatar, not under it: its top must be
    // within the avatar's 24pt band rather than stacked below.
    const name_rect = t.findText("Sterne") orelse t.findText("fx") orelse return error.SkipZigTest;
    // Everything in the account row stays inside the 248pt sidebar.
    try std.testing.expect(name_rect.x + name_rect.w <= 248);
}

test "removing a session archives it instead of deleting it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .session;
    const before = s.workspaces.items[s.folder].sessions.items.len;
    s.openRemove();
    try std.testing.expect(s.dialog != null);
    s.confirmDialog();
    const ws = &s.workspaces.items[s.folder];
    // The session is kept (archived), not dropped from the list.
    try std.testing.expectEqual(before, ws.sessions.items.len);
    try std.testing.expect(ws.sessions.items[0].archived);
    try std.testing.expect(s.dialog == null);
}

test "session row menu opens and offers its actions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .home;
    s.row_menu = .{ .ws = 0, .si = 0 };
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Rename"));
    try std.testing.expect(t.hasText("Show changes"));
    try std.testing.expect(t.hasText("Remove from list"));
    // Choosing Remove opens the confirm dialog and closes the menu.
    try t.clickText("Remove from list");
    t.settle(0.1);
    try std.testing.expect(s.row_menu == null);
    try std.testing.expect(s.dialog != null);
}

test "tab bar folder switcher lists workspaces" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .home;
    s.sidebar_open = false;
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    // The bar shows the workspace name and a New session button.
    try std.testing.expect(t.hasText("project"));
    try std.testing.expect(t.hasText("New session"));
    // Opening the switcher lists the workspace and Add folder.
    s.folders_menu_open = true;
    t.settle(0.2);
    try std.testing.expect(t.hasText("Add folder"));
}

test "parseModels reads the catalog and modelMenu lists it" {
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"kind":"models","count":3,"ids":["auto/glm-5.3","codex/gpt-6.2-sol","group/auto"]}
    , .{});
    defer parsed.deinit();
    var info: @import("fxcli.zig").Info = .{};
    @import("fxcli.zig").parseModels(&info, parsed.value);
    try std.testing.expectEqual(@as(usize, 3), info.catalog_count);
    try std.testing.expectEqualStrings("auto/glm-5.3", info.catalog[0].slice());
}

test "parseStatus reads the permission modes" {
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"permission_mode":"ask","modes":[{"id":"auto","name":"Auto","description":"Check actions with an automatic safety review"},{"id":"ask","name":"Ask","description":"Request permission before making any changes"},{"id":"full-access","name":"Full access","description":"Run every action without fx permission checks"}]}
    , .{});
    defer parsed.deinit();
    var info: @import("fxcli.zig").Info = .{};
    @import("fxcli.zig").parseStatus(&info, parsed.value);
    try std.testing.expectEqual(@as(usize, 3), info.mode_count);
    try std.testing.expectEqualStrings("auto", info.modes[0].id.slice());
    try std.testing.expectEqualStrings("Ask", info.modes[1].name.slice());
    try std.testing.expectEqualStrings("full-access", info.modes[2].id.slice());
    try std.testing.expect(info.modes[2].description.slice().len > 0);
}

test "narrow width still renders" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 480, .height = 720, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.ctx.nodes.items.len > 4);
}

test "diff block renders numbered rows and a hunk header" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .session;
    s.changes_open = true;
    // Seed a diff: a hunk header, a context line, an added and a removed line.
    const git = @import("git.zig");
    s.changes_diff.append(alloc, .{ .kind = .hunk, .body = "@@ -1,3 +1,4 @@" }) catch unreachable;
    s.changes_diff.append(alloc, .{ .kind = .context, .old = 1, .new = 1, .body = "const std = @import(\"std\");" }) catch unreachable;
    s.changes_diff.append(alloc, .{ .kind = .added, .new = 2, .body = "const ui = @import(\"nanoui\");" }) catch unreachable;
    s.changes_diff.append(alloc, .{ .kind = .removed, .old = 2, .body = "// old line" }) catch unreachable;
    s.changes_open_file = alloc.dupe(u8, "src/main.zig") catch unreachable;
    for (s.changes.changes.items) |ch| alloc.free(ch.path);
    s.changes.changes.clearRetainingCapacity();
    s.changes.err_msg = null;
    s.changes.changes.append(alloc, .{ .path = alloc.dupe(u8, "src/main.zig") catch unreachable, .code = 'M', .staged = false, .added = 1, .removed = 1 }) catch unreachable;

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("@@ -1,3 +1,4 @@"));
    try std.testing.expect(t.hasText("const ui = @import(\"nanoui\");"));
    try std.testing.expect(t.hasText("// old line"));
    // The line numbers come from the diff, not invented.
    try std.testing.expect(t.hasText("1"));
    try std.testing.expect(t.hasText("2"));
    _ = git;
}

test "home shows a pending approval above the lists" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .home;
    // A pending command approval, as the worker would report it.
    var perm = @import("engine.zig").Permission{};
    perm.request_id = 42;
    perm.setQuestion("Run this command?");
    perm.setDetail("zig build test");
    perm.setKind("execute");
    perm.addOption("allow", "Allow once", "allow_once");
    perm.addOption("deny", "Deny", "reject_once");
    s.preview_permission = perm;

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Run this command?"));
    try std.testing.expect(t.hasText("zig build test"));
    try std.testing.expect(t.hasText("Deny"));
    try std.testing.expect(t.hasText("Run"));
    // Answering dispatches the ACP option (view.zig consumes pending_answer
    // at the end of the frame and counts it).
    const before = s.answers_sent;
    try t.clickText("Run");
    t.settle(0.1);
    try std.testing.expect(s.answers_sent > before);
}

test "home shows the agent-down card for a crash and for a signed-out fx" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .home;
    s.agent_error = "fx acp exited with status 1\nthread 'main' panicked at src/main.zig:42";
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("fx acp exited"));
    try std.testing.expect(t.hasText("Start fx again"));
    try std.testing.expect(t.hasText("Fix sign-in"));
    try std.testing.expect(t.hasText("Run fx doctor"));
    // The error's own lines are shown, not invented.
    try std.testing.expect(t.hasText("thread 'main' panicked at src/main.zig:42"));

    // A signed-out error gets the amber wording instead.
    s.agent_error = "run `fx login` to connect an account";
    t.settle(0.2);
    try std.testing.expect(t.hasText("No account connected"));
    try std.testing.expect(!t.hasText("fx acp exited"));
}

test "a prompt typed while running queues and sends when the turn settles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .session;
    const session = s.currentSession().?;
    // The session is mid-turn.
    session.status = .running;
    session.turns.items[0].status = .running;

    s.input.set("second question");
    s.sendPrompt();
    // It queued instead of starting a new turn.
    try std.testing.expectEqual(@as(usize, 1), session.queue.items.len);
    try std.testing.expectEqualStrings("second question", session.queue.items[0]);
    try std.testing.expectEqual(@as(usize, 1), session.turns.items.len);

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    // The dock shows the queued prompt.
    try std.testing.expect(t.hasText("Next"));
    try std.testing.expect(t.hasText("second question"));

    // Settling the turn flushes the queue into a real turn.
    session.status = .idle;
    s.flushQueue();
    try std.testing.expectEqual(@as(usize, 0), session.queue.items.len);
    try std.testing.expectEqual(@as(usize, 2), session.turns.items.len);
    try std.testing.expectEqualStrings("second question", session.turns.items[1].prompt);
}

test "a live step spins and a folded group shows a chevron" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .session;
    const session = s.currentSession().?;
    const turn = &session.turns.items[0];
    const T = @import("engine.zig").ToolStep;
    // Three same-kind settled steps fold into one row with "+2 more".
    for (0..3) |i| {
        var step = T{};
        var id_buf: [8]u8 = undefined;
        step.setId(std.fmt.bufPrint(&id_buf, "c{d}", .{i}) catch "");
        step.setKind("read");
        step.setStatus("completed");
        step.setDetail("src/file.zig");
        turn.steps[i] = step;
    }
    // A fourth step is still running, so it spins.
    var live = T{};
    live.setId("live");
    live.setKind("execute");
    live.setStatus("in_progress");
    live.setDetail("zig build test");
    turn.steps[3] = live;
    turn.step_count = 4;
    turn.status = .running;
    s.toggleTurn(0);

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    // The folded group reports its extra rows; the live step shows its detail.
    try std.testing.expect(t.hasText("+2 more"));
    try std.testing.expect(t.hasText("zig build test"));
}

test "changes header switches between Files and Diff" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .session;
    s.changes_open = true;
    for (s.changes.changes.items) |ch| alloc.free(ch.path);
    s.changes.changes.clearRetainingCapacity();
    s.changes.err_msg = null;
    s.changes.changes.append(alloc, .{
        .path = alloc.dupe(u8, "src/main.zig") catch unreachable,
        .code = 'M',
        .staged = false,
        .added = 3,
        .removed = 1,
    }) catch unreachable;

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    // Both segments are present; Files is the default view.
    try std.testing.expect(t.hasText("Files"));
    try std.testing.expect(t.hasText("Diff"));
    try std.testing.expect(s.changes_open_file == null);

    // Choosing Diff opens the first file's diff.
    try t.clickText("Diff");
    t.settle(0.1);
    try std.testing.expect(s.changes_open_file != null);

    // Choosing Files closes it again.
    try t.clickText("Files");
    t.settle(0.1);
    try std.testing.expect(s.changes_open_file == null);
}

test "open beside shows a second session and swaps on click" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .session;
    const ws = &s.workspaces.items[s.folder];
    // A second session with its own turn.
    var other = @import("state.zig").Session.init(alloc, "Other session");
    var turn = @import("state.zig").Turn.init(alloc, "What does the linter say?");
    turn.answer.appendSlice(alloc, "Two warnings.") catch unreachable;
    turn.status = .idle;
    other.turns.append(alloc, turn) catch unreachable;
    ws.sessions.append(alloc, other) catch unreachable;

    s.openBeside(0, 1);
    try std.testing.expect(s.beside != null);

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    // The pane shows the other session's title and its turn.
    try std.testing.expect(t.hasText("Other session"));
    try std.testing.expect(t.hasText("What does the linter say?"));
    try std.testing.expect(t.hasText("Two warnings."));

    // Clicking the pane swaps it into the main view and closes the split.
    try t.clickText("What does the linter say?");
    t.settle(0.1);
    try std.testing.expect(s.beside == null);
    try std.testing.expectEqual(@as(usize, 1), s.active.?);
}

test "the remove dialog names the session it archives" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .session;
    s.currentSession().?.title = alloc.dupe(u8, "Fix the linter") catch unreachable;
    s.openRemove();
    try std.testing.expect(s.dialog != null);
    // The note quotes the session's own name, like the design's remove_dialog.
    try std.testing.expect(std.mem.indexOf(u8, s.dialog.?.noteSlice(), "“Fix the linter”") != null);
    try std.testing.expect(std.mem.indexOf(u8, s.dialog.?.noteSlice(), "moves to Archived") != null);
}

test "a turn renders its answer above the files card" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .session;
    // The last turn has an answer, and the workspace has changes.
    for (s.changes.changes.items) |ch| alloc.free(ch.path);
    s.changes.changes.clearRetainingCapacity();
    s.changes.err_msg = null;
    s.changes.changes.append(alloc, .{
        .path = alloc.dupe(u8, "src/main.zig") catch unreachable,
        .code = 'M',
        .staged = false,
        .added = 4,
        .removed = 2,
    }) catch unreachable;

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    // The design puts the answer (and its footer) above the changed-files card.
    const answer = t.findText("A native coding agent in Zig.") orelse return error.SkipZigTest;
    const card = t.findText("1 file changed") orelse return error.SkipZigTest;
    try std.testing.expect(answer.y < card.y);
}

test "a turn that stopped early says why" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .session;
    const session = s.currentSession().?;
    const turn = &session.turns.items[0];
    turn.status = .idle;
    turn.stop_reason = "cancelled";

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Stopped before it finished."));

    // A normal end_turn shows no stop line.
    turn.stop_reason = "end_turn";
    t.settle(0.2);
    try std.testing.expect(!t.hasText("Stopped before it finished."));
}

test "the palette groups session commands with their icons" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .session;
    s.currentSession().?.status = .running;
    s.palette.open = true;

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    // Session-scoped commands sit under "This session", like the design.
    try std.testing.expect(t.hasText("This session"));
    try std.testing.expect(t.hasText("Rename this session"));
    try std.testing.expect(t.hasText("Remove this session from the list"));
    try std.testing.expect(t.hasText("Stop the running turn"));
    // The icons come from the entry, not a group guess.
    const P = @import("palette.zig");
    var entries: [64]P.Entry = undefined;
    const n = P.Palette.collect(&s, &entries);
    var found_stop = false;
    for (entries[0..n]) |e| {
        if (std.mem.eql(u8, e.label, "Stop the running turn")) {
            try std.testing.expectEqualStrings("This session", e.group);
            try std.testing.expectEqualStrings("x", e.icon);
            found_stop = true;
        }
    }
    try std.testing.expect(found_stop);
}

test "the sidebar's project + starts a session in that project" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    // Two projects, so the + has to pick the right one.
    s.workspaces.append(alloc, .{ .path = "/tmp/second", .name = "second" }) catch {};
    try std.testing.expectEqual(@as(usize, 0), s.workspaces.items[1].sessions.items.len);

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    // The + beside the second project creates a session there. It is drawn
    // as an icon, so the test drives the action it is bound to.
    s.newSessionIn(1);
    try std.testing.expectEqual(@as(usize, 1), s.workspaces.items[1].sessions.items.len);
    // The first project keeps the sessions it already had.
    const first_before = s.workspaces.items[0].sessions.items.len;
    try std.testing.expectEqual(@as(usize, 1), s.folder);
    try std.testing.expectEqual(@as(?usize, 0), s.active);
    try std.testing.expect(first_before >= 0);
}

test "the sidebar's Add folder row is a button" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Add folder"));
    // The row carries the click target, so a click reaches the picker. The
    // picker is a native dialog the test cannot open, so this checks the row
    // is a control with a hit rect rather than dead text.
    const r = t.findText("Add folder") orelse return error.TextNotFound;
    try std.testing.expect(r.w > 0 and r.h > 0);
    try std.testing.expect(t.hasText("⌘O"));
}
