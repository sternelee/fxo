//! Permission approval card, mirroring fx-ui-main/src/views/thread/prompts.rs.
const std = @import("std");
const ui = @import("nanoui").ui;
const t = @import("tokens.zig");
const w = @import("widgets.zig");
const eng = @import("engine.zig");

pub fn view(p: *const eng.Permission, c: *ui.Context, ctx: *anyopaque, on_answer: *const fn (*anyopaque, ?[]const u8) void) void {
    const card = ui.div(c).column().wFull().gap(12).p(14).rounded(12)
        .bg(t.gray_100).border(t.alpha_400).borderW(1);
    defer card.end();

    {
        const head = ui.div(c).row().wFull().gap(10).itemsCenter().px(2);
        defer head.end();
        w.dot(c, t.amber_700);
        ui.text(c, p.questionSlice(), .{ .size = 14, .line_height = 20, .weight = .medium, .color = t.gray_1000 });
        const kind = p.kindSlice();
        const note: []const u8 = if (std.mem.eql(u8, kind, "read"))
            "to read files in the workspace"
        else if (std.mem.eql(u8, kind, "edit"))
            "to edit files in the workspace"
        else if (std.mem.eql(u8, kind, "execute"))
            "to run a command"
        else if (std.mem.eql(u8, kind, "fetch"))
            "to fetch from the web"
        else
            "";
        if (note.len > 0) ui.text(c, note, .{ .size = 14, .line_height = 20, .color = t.gray_900 });
    }

    if (p.diff_count > 0) {
        // Diff preview: file header with counts, then colored numbered rows.
        const diff = ui.div(c).column().wFull().rounded(8).border(t.alpha_200).borderW(1).clip();
        defer diff.end();
        {
            const head = ui.div(c).row().wFull().h(34).px(12).gap(10).itemsCenter().bg(t.gray_200);
            defer head.end();
            ui.text(c, p.detailSlice(), .{ .size = 12, .line_height = 16, .mono = true, .family = t.mono_family, .truncate = .ellipsis, .color = t.gray_900 });
            {
                const spacer = ui.div(c).grow();
                defer spacer.end();
            }
            if (p.diff_added > 0) ui.text(c, c.print("+{d}", .{p.diff_added}), .{ .size = 12, .mono = true, .family = t.mono_family, .color = t.green_900 });
            if (p.diff_removed > 0) ui.text(c, c.print("−{d}", .{p.diff_removed}), .{ .size = 12, .mono = true, .family = t.mono_family, .color = t.red_900 });
        }
        {
            const body = ui.div(c).column().wFull().py(4).bg(t.background_200);
            defer body.end();
            for (p.diff[0..p.diff_count]) |row| {
                const bg: ?ui.Color = switch (row.kind) {
                    .added => .{ .r = 0.27, .g = 0.65, .b = 0.34, .a = 0.16 },
                    .removed => .{ .r = 0.90, .g = 0.28, .b = 0.30, .a = 0.13 },
                    .context => null,
                };
                const line = ui.div(c).row().wFull().h(22).itemsCenter().bg(bg orelse t.background_200);
                defer line.end();
                const num = switch (row.kind) {
                    .added => row.new_no,
                    .removed => row.old_no,
                    .context => row.new_no,
                };
                const num_color: ui.Color = switch (row.kind) {
                    .added => t.green_900,
                    .removed => t.red_900,
                    .context => t.gray_600,
                };
                ui.text(c, if (num > 0) c.print("{d}", .{num}) else "", .{ .size = 12, .mono = true, .family = t.mono_family, .color = num_color });
                ui.text(c, row.textSlice(), .{ .size = 12, .line_height = 22, .mono = true, .family = t.mono_family, .truncate = .ellipsis, .color = if (row.kind == .context) t.gray_900 else t.gray_1000 });
            }
        }
    } else {
        const preview = ui.div(c).row().wFull().px(12).py(10).rounded(8).bg(t.background_200);
        defer preview.end();
        if (p.isExecute()) ui.text(c, "$ ", .{ .size = 13, .line_height = 20, .mono = true, .family = t.mono_family, .color = t.gray_700 });
        ui.text(c, p.detailSlice(), .{ .size = 13, .line_height = 20, .wrap = true, .mono = true, .family = t.mono_family, .color = t.gray_1000 });
    }

    {
        const buttons = ui.div(c).row().wFull().gap(8).itemsCenter();
        defer buttons.end();
        if (p.byKind("allow_always")) |always| {
            const dir = std.fs.path.dirname(p.detailSlice()) orelse "";
            const label = if (p.isExecute())
                "Always allow"
            else if (dir.len > 0)
                c.print("Always allow edits in {s}/", .{dir})
            else
                "Always allow in this session";
            if (w.button(c, "perm-always", label, false)) on_answer(ctx, always.idSlice());
        }
        {
            const spacer = ui.div(c).grow();
            defer spacer.end();
        }
        const reject = p.byKind("reject_once") orelse p.byKind("reject_always");
        if (w.button(c, "perm-deny", "Deny   Esc", false)) on_answer(ctx, if (reject) |r| r.idSlice() else null);
        if (p.defaultAllow()) |allow| {
            const label = if (p.isExecute()) "Run   ⌘⏎" else "Allow   ⌘⏎";
            if (w.button(c, "perm-allow", label, true)) on_answer(ctx, allow.idSlice());
        }
    }
}
