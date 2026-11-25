//! Unified-diff rendering shared by the changes panel and the permission card,
//! mirroring fx-ui-main/src/views/diff.rs.
const std = @import("std");
const ui = @import("nanoui").ui;
const t = @import("tokens.zig");
const git = @import("git.zig");

/// One diff row: a 40pt right-aligned line number, then the body.
/// Hunk headers are 26pt and carry no number.
fn diffRow(c: *ui.Context, line: git.DiffLine) void {
    if (line.kind == .hunk) {
        const row = ui.div(c).row().wFull().h(26).px(14).itemsCenter();
        defer row.end();
        ui.text(c, line.body, .{ .size = 12, .line_height = 16, .mono = true, .family = t.mono_family, .truncate = .ellipsis, .color = t.gray_700 });
        return;
    }
    const bg: ui.Color = switch (line.kind) {
        .added => .{ .r = 0.27, .g = 0.65, .b = 0.34, .a = 0.12 },
        .removed => .{ .r = 0.90, .g = 0.28, .b = 0.30, .a = 0.10 },
        .context, .hunk => t.background_200,
    };
    const num = switch (line.kind) {
        .added => line.new,
        .removed => line.old,
        else => line.new,
    };
    const num_color: ui.Color = switch (line.kind) {
        .added => t.green_900,
        .removed => t.red_900,
        else => t.gray_600,
    };
    const row = ui.div(c).row().wFull().h(22).itemsCenter().bg(bg);
    defer row.end();
    {
        // The number column keeps a fixed width so bodies line up.
        const gutter = ui.div(c).row().w(40).pr(12).justifyEnd().itemsCenter();
        defer gutter.end();
        ui.text(c, if (num) |n| c.print("{d}", .{n}) else "", .{ .size = 12, .line_height = 22, .mono = true, .family = t.mono_family, .color = num_color });
    }
    {
        const body = ui.div(c).row().grow().pr(12).itemsCenter();
        defer body.end();
        ui.text(c, line.body, .{ .size = 12, .line_height = 22, .mono = true, .family = t.mono_family, .truncate = .ellipsis, .color = if (line.kind == .context) t.gray_900 else t.gray_1000 });
    }
}

/// The block: a background-200 column with 6pt vertical padding.
pub fn block(c: *ui.Context, lines: []const git.DiffLine, limit: usize) void {
    if (lines.len == 0) return;
    const shown = @min(lines.len, limit);
    const box = ui.div(c).column().wFull().py(6).bg(t.background_200);
    defer box.end();
    for (lines[0..shown]) |line| diffRow(c, line);
}

/// "Show N more lines", centered, 30pt tall.
pub fn moreLines(c: *ui.Context, id: []const u8, hidden: usize) bool {
    ui.key(c, id);
    const row = ui.div(c).row().wFull().h(30).center().control();
    defer row.end();
    ui.text(c, c.print("Show {d} more line{s}", .{ hidden, if (hidden == 1) "" else "s" }), .{ .size = 12, .line_height = 16, .color = t.gray_700 });
    return row.clicked();
}
