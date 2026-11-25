//! The fx icon set, transcribed 1:1 from fx-ui-main/src/design/assets.rs.
//! Each entry is the inner SVG of a 16x16 viewBox with white stroke; nanoui
//! tints it to the requested color via ui.svg.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const t = @import("tokens.zig");

pub const Icon = struct { name: []const u8, width: []const u8, body: []const u8 };

pub const icons = [_]Icon{
    .{ .name = "panel-left", .width = "1.4", .body = "<rect x=\"2\" y=\"2.75\" width=\"12\" height=\"10.5\" rx=\"2\"/><path d=\"M6 2.75v10.5\"/>" },
    .{ .name = "panel-split", .width = "1.4", .body = "<rect x=\"2\" y=\"2.75\" width=\"12\" height=\"10.5\" rx=\"2\"/><path d=\"M8 2.75v10.5\"/>" },
    .{ .name = "panel-right", .width = "1.4", .body = "<rect x=\"2\" y=\"2.75\" width=\"12\" height=\"10.5\" rx=\"2\"/><path d=\"M10 2.75v10.5\"/>" },
    .{ .name = "compose", .width = "1.4", .body = "<path d=\"M12.5 8.5V12a1.5 1.5 0 01-1.5 1.5H4A1.5 1.5 0 012.5 12V5A1.5 1.5 0 014 3.5h3.5\" stroke-linecap=\"round\"/><path d=\"M11.5 2.5l2 2L8 10H6V8l5.5-5.5z\" stroke-linejoin=\"round\"/>" },
    .{ .name = "search", .width = "1.4", .body = "<circle cx=\"7\" cy=\"7\" r=\"4.5\"/><path d=\"M10.5 10.5L13.5 13.5\" stroke-linecap=\"round\"/>" },
    .{ .name = "star", .width = "1.4", .body = "<path d=\"M8 2l1.6 3.6L13.5 6l-2.9 2.6.8 3.9L8 10.6 4.6 12.5l.8-3.9L2.5 6l3.9-.4L8 2z\" stroke-linejoin=\"round\"/>" },
    .{ .name = "plus", .width = "1.4", .body = "<path d=\"M8 3.5v9M3.5 8h9\" stroke-linecap=\"round\"/>" },
    .{ .name = "plus-lg", .width = "1.5", .body = "<path d=\"M8 3v10M3 8h10\" stroke-linecap=\"round\"/>" },
    .{ .name = "settings", .width = "1.4", .body = "<circle cx=\"8\" cy=\"8\" r=\"2\"/><path d=\"M8 1.75v1.5M8 12.75v1.5M1.75 8h1.5M12.75 8h1.5M3.6 3.6l1.05 1.05M11.35 11.35l1.05 1.05M3.6 12.4l1.05-1.05M11.35 4.65l1.05-1.05\" stroke-linecap=\"round\"/>" },
    .{ .name = "shield", .width = "1.4", .body = "<path d=\"M8 1.75l5 2v4c0 3-2.2 5.3-5 6.5-2.8-1.2-5-3.5-5-6.5v-4l5-2z\" stroke-linejoin=\"round\"/>" },
    .{ .name = "chevron-down", .width = "1.5", .body = "<path d=\"M4 6l4 4 4-4\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>" },
    .{ .name = "chevron-right", .width = "1.5", .body = "<path d=\"M6 3.5L10.5 8 6 12.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>" },
    .{ .name = "branch", .width = "1.4", .body = "<circle cx=\"4.5\" cy=\"3.5\" r=\"1.75\"/><circle cx=\"4.5\" cy=\"12.5\" r=\"1.75\"/><circle cx=\"11.5\" cy=\"5.5\" r=\"1.75\"/><path d=\"M4.5 5.25v5.5M11.5 7.25c0 2.5-3 2.5-6.5 3.5\"/>" },
    .{ .name = "arrow-up", .width = "1.75", .body = "<path d=\"M8 13V3M3.5 7.5L8 3l4.5 4.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>" },
    .{ .name = "ellipsis", .width = "0", .body = "<circle cx=\"3.5\" cy=\"8\" r=\"1\" fill=\"#fff\"/><circle cx=\"8\" cy=\"8\" r=\"1\" fill=\"#fff\"/><circle cx=\"12.5\" cy=\"8\" r=\"1\" fill=\"#fff\"/>" },
    .{ .name = "check", .width = "1.5", .body = "<path d=\"M3.5 8.5l3 3 6-7\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>" },
    .{ .name = "x", .width = "1.5", .body = "<path d=\"M4 4l8 8M12 4l-8 8\" stroke-linecap=\"round\"/>" },
    .{ .name = "file", .width = "1.4", .body = "<path d=\"M9 2H4.5A1.5 1.5 0 003 3.5v9A1.5 1.5 0 004.5 14h7a1.5 1.5 0 001.5-1.5V6L9 2z\" stroke-linejoin=\"round\"/>" },
    .{ .name = "folder", .width = "1.4", .body = "<path d=\"M2.5 4.5A1.5 1.5 0 014 3h2.5l1.5 1.5h4A1.5 1.5 0 0113.5 6v5.5A1.5 1.5 0 0112 13H4a1.5 1.5 0 01-1.5-1.5v-7z\" stroke-linejoin=\"round\"/>" },
    .{ .name = "lines", .width = "1.4", .body = "<path d=\"M3 4.5h10M3 8h10M3 11.5h6\" stroke-linecap=\"round\"/>" },
    .{ .name = "user", .width = "1.4", .body = "<circle cx=\"8\" cy=\"6\" r=\"2.5\"/><path d=\"M3 13.5c.8-2.3 2.7-3.5 5-3.5s4.2 1.2 5 3.5\" stroke-linecap=\"round\"/>" },
    .{ .name = "alert", .width = "1.75", .body = "<path d=\"M8 4.5v4M8 11v.01\" stroke-linecap=\"round\"/>" },
    .{ .name = "pencil", .width = "1.4", .body = "<path d=\"M11 2.5l2.5 2.5L6 12.5H3.5V10L11 2.5z\" stroke-linejoin=\"round\"/>" },
    .{ .name = "copy", .width = "1.4", .body = "<rect x=\"5\" y=\"5\" width=\"8.5\" height=\"8.5\" rx=\"1.5\"/><path d=\"M3 10.5V3.5A1 1 0 014 2.5h7\" stroke-linecap=\"round\"/>" },
    .{ .name = "trash", .width = "1.4", .body = "<path d=\"M3 4.5h10M6.5 4.5V3h3v1.5M4.5 4.5l.6 8.5h5.8l.6-8.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>" },
    .{ .name = "terminal", .width = "1.4", .body = "<path d=\"M3 4.5L6.5 8 3 11.5M8.5 11.5H13\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>" },
    .{ .name = "globe", .width = "1.4", .body = "<circle cx=\"8\" cy=\"8\" r=\"5.75\"/><path d=\"M2.25 8h11.5M8 2.25c2.2 2 2.2 9.5 0 11.5M8 2.25c-2.2 2-2.2 9.5 0 11.5\"/>" },
    .{ .name = "bolt", .width = "1.4", .body = "<path d=\"M9 1.75L3.5 9h4l-.5 5.25L12.5 7h-4L9 1.75z\" stroke-linejoin=\"round\"/>" },
    .{ .name = "image", .width = "1.4", .body = "<rect x=\"2\" y=\"3\" width=\"12\" height=\"10\" rx=\"2\"/><circle cx=\"5.75\" cy=\"6.5\" r=\"1.1\" fill=\"#fff\" stroke=\"none\"/><path d=\"M2.5 11.5l3.5-3 2.5 2 2-1.5 3 2.5\" stroke-linejoin=\"round\"/>" },
    .{ .name = "sun", .width = "1.4", .body = "<circle cx=\"8\" cy=\"8\" r=\"3\"/><path d=\"M8 1.75v1.5M8 12.75v1.5M1.75 8h1.5M12.75 8h1.5M3.6 3.6l1.05 1.05M11.35 11.35l1.05 1.05M3.6 12.4l1.05-1.05M11.35 4.65l1.05-1.05\" stroke-linecap=\"round\"/>" },
    .{ .name = "spin-track", .width = "2", .body = "<circle cx=\"8\" cy=\"8\" r=\"6\"/>" },
    .{ .name = "spin-arc", .width = "2", .body = "<path d=\"M8 2a6 6 0 0 1 6 6\" stroke-linecap=\"round\"/>" },
    // Additional icons used by the app, matching the archive's stroke style.
    .{ .name = "history", .width = "1.4", .body = "<path d=\"M3 8a5 5 0 1 0 1.5-3.5M3 3v2.5h2.5M8 5v3l2 1.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>" },
    .{ .name = "plug", .width = "1.4", .body = "<path d=\"M5 2v3M11 2v3M3.5 5h9v2.5a4.5 4.5 0 01-9 0V5zM8 12v2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>" },
    .{ .name = "square", .width = "1.4", .body = "<rect x=\"3\" y=\"3\" width=\"10\" height=\"10\" rx=\"2\"/>" },
    .{ .name = "external-link", .width = "1.4", .body = "<path d=\"M9 3h4v4M13 3L7 9M11 9v3a1 1 0 01-1 1H4a1 1 0 01-1-1V6a1 1 0 011-1h3\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>" },
};

fn svgFor(name: []const u8) ?Icon {
    for (icons) |icon| if (std.mem.eql(u8, icon.name, name)) return icon;
    return null;
}

/// Builds the full SVG document for an icon, in `a`'s memory.
pub fn document(a: std.mem.Allocator, name: []const u8) ?[]const u8 {
    const icon = svgFor(name) orelse return null;
    return std.fmt.allocPrint(a, "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 16 16\" fill=\"none\" stroke=\"#fff\" stroke-width=\"{s}\">{s}</svg>", .{ icon.width, icon.body }) catch null;
}

/// Draws a named icon at `size` points, tinted to `color`.
pub fn draw(c: *ui.Context, name: []const u8, size: f32, color: ui.Color) void {
    const doc = document(c.alloc(), name) orelse return;
    _ = ui.svg(c, .{ .key = name, .bytes = doc, .size = size, .color = color });
}

test "every icon has a name and a body" {
    for (icons) |icon| {
        try std.testing.expect(icon.name.len > 0);
        try std.testing.expect(icon.body.len > 0);
    }
    const doc = document(std.testing.allocator, "search").?;
    defer std.testing.allocator.free(doc);
    try std.testing.expect(std.mem.indexOf(u8, doc, "viewBox=\"0 0 16 16\"") != null);
    try std.testing.expect(document(std.testing.allocator, "nope") == null);
}
