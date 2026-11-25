//! Menu, dialog and interaction tests: headless, no window, no fx process.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const view = @import("view.zig");
const fixture = @import("tests.zig").fixture;

test "home shows the install page when fx is missing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .home;
    s.agent_error = "error: Unable to spawn: FileNotFound (fx: not found)";
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("fx is not installed"));
    try std.testing.expect(t.hasText("Start again"));
    try std.testing.expect(t.hasText("Copy command"));
    // Copying puts the command on the clipboard.
    try t.clickText("Copy command");
    t.settle(0.1);
    try std.testing.expect(t.clipboard.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, t.clipboard.items, "fx.sh/setup.sh") != null);
}

test "home shows the first-run steps with no workspace" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = view.State.init(alloc);
    s.page = .home;
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Welcome to fx"));
    try std.testing.expect(t.hasText("Open a folder"));
    try std.testing.expect(t.hasText("Connect a model"));
    // Connect jumps to Settings > Models.
    try t.clickText("Connect");
    t.settle(0.1);
    try std.testing.expect(s.page == .settings);
    try std.testing.expect(s.settings_section == .models);
}

test "an approval card shows the edit size" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.preview_permission = .{
        .request_id = 7,
        .diff_count = 3,
        .diff_added = 37,
        .diff_removed = 19,
    };
    @memcpy(s.preview_permission.?.question[0..9], "Edit a.ts");
    s.preview_permission.?.question_len = 9;

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    // The card says how much the edit changes, so the user can judge it.
    // The text system sets a hyphen as a typographic minus (U+2212).
    try std.testing.expect(t.containsText("+37"));
    try std.testing.expect(t.containsText("−19"));
    try std.testing.expect(t.containsText("Deny"));
}
