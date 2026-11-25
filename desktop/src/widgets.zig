//! Shared controls transcribed from fx-ui-main/src/design/components.rs.
const ui = @import("nanoui").ui;
const t = @import("tokens.zig");

pub fn textStyle(size: f32, line_height: f32) ui.TextStyle {
    return .{ .size = size, .line_height = line_height, .color = t.gray_1000 };
}

pub fn muted(size: f32, line_height: f32) ui.TextStyle {
    return .{ .size = size, .line_height = line_height, .color = t.gray_900 };
}

pub fn faint(size: f32, line_height: f32) ui.TextStyle {
    return .{ .size = size, .line_height = line_height, .color = t.gray_700 };
}

/// A 32pt pill button with 12pt horizontal padding, 8pt radius.
pub fn button(c: *ui.Context, id: []const u8, label: []const u8, primary: bool) bool {
    ui.key(c, id);
    const box = ui.div(c).row().itemsCenter().h(32).px(12).gap(8).rounded(8).control()
        .bg(if (primary) t.gray_1000 else t.gray_100)
        .hover(if (primary) t.white else t.alpha_200);
    defer box.end();
    ui.text(c, label, .{ .size = 13, .line_height = 18, .weight = .medium, .color = if (primary) t.background_100 else t.gray_1000 });
    return box.clicked();
}

/// A 28pt icon button, 6pt radius, hover alpha. `name` is an fx icon name.
pub fn iconButton(c: *ui.Context, id: []const u8, name: []const u8) bool {
    const box = ui.div(c).size(28, 28).rounded(6).control().center().hover(t.alpha_200);
    defer box.end();
    ui.key(c, id);
    @import("icons.zig").draw(c, name, 16, t.gray_900);
    return box.clicked();
}

/// A 14pt spinner: track + rotating arc, like the design's components.rs.
pub fn spinner(c: *ui.Context, id: []const u8, color: ui.Color) void {
    const icons = @import("icons.zig");
    ui.key(c, c.print("{s}-track", .{id}));
    const box = ui.div(c).size(14, 14).center();
    defer box.end();
    icons.draw(c, "spin-track", 14, t.gray_400);
    const frame = ui.motion.keyframes(c, .{
        .values = &.{
            .{ .rotation = 0 },
            .{ .rotation = @import("std").math.tau },
        },
        .duration = 0.9,
        .repeat = null,
        .ease = .linear,
    });
    ui.key(c, c.print("{s}-arc", .{id}));
    const arc = ui.div(c).size(14, 14).center().motion(frame);
    defer arc.end();
    icons.draw(c, "spin-arc", 14, color);
}

/// A 7pt status dot.
pub fn dot(c: *ui.Context, color: ui.Color) void {
    const box = ui.div(c).size(7, 7).rounded(4).bg(color);
    defer box.end();
}

/// A nav row in the sidebar: 30pt tall, 8pt padding, 6pt radius.
pub fn nav(c: *ui.Context, id: []const u8, icon_name: []const u8, label: []const u8, keys: []const u8, on: bool) bool {
    ui.key(c, id);
    const box = ui.div(c).row().itemsCenter().h(30).wFull().px(8).gap(10).rounded(6).control()
        .bg(if (on) t.alpha_200 else t.background_200).hover(t.alpha_200);
    defer box.end();
    @import("icons.zig").draw(c, icon_name, 16, t.gray_1000);
    ui.text(c, label, textStyle(13, 18));
    {
        const spacer = ui.div(c).grow();
        defer spacer.end();
    }
    if (keys.len > 0) ui.text(c, keys, faint(12, 16));
    return box.clicked();
}

/// A composer pill: 32pt tall, 16pt radius, hover alpha.
pub fn pill(c: *ui.Context, id: []const u8, label: []const u8, border: bool) bool {
    ui.key(c, id);
    const box = ui.div(c).row().itemsCenter().h(32).px(12).gap(6).rounded(16).control().hover(t.alpha_200)
        .border(if (border) t.alpha_400 else t.background_100).borderW(if (border) 1 else 0);
    defer box.end();
    ui.text(c, label, textStyle(13, 18));
    return box.clicked();
}
