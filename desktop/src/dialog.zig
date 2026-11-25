//! Confirm/rename/full-access dialogs, mirroring fx-ui-main/src/views/dialogs.rs.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const t = @import("tokens.zig");
const w = @import("widgets.zig");
const State = @import("state.zig").State;

pub const Kind = enum { remove, rename, full_access, discard };

pub const Dialog = struct {
    kind: Kind = .remove,
    title: [128]u8 = undefined,
    title_len: usize = 0,
    note: [256]u8 = undefined,
    note_len: usize = 0,
    target: [256]u8 = undefined,
    target_len: usize = 0,

    pub fn titleSlice(d: *const Dialog) []const u8 {
        return d.title[0..d.title_len];
    }
    pub fn noteSlice(d: *const Dialog) []const u8 {
        return d.note[0..d.note_len];
    }
    pub fn targetSlice(d: *const Dialog) []const u8 {
        return d.target[0..d.target_len];
    }
    pub fn setTitle(d: *Dialog, v: []const u8) void {
        d.title_len = copy(&d.title, v);
    }
    pub fn setNote(d: *Dialog, v: []const u8) void {
        d.note_len = copy(&d.note, v);
    }
    pub fn setTarget(d: *Dialog, v: []const u8) void {
        d.target_len = copy(&d.target, v);
    }
};

fn copy(dest: []u8, src: []const u8) usize {
    const n = @min(dest.len, src.len);
    @memcpy(dest[0..n], src[0..n]);
    return n;
}

pub fn view(s: *State, c: *ui.Context) void {
    const d = s.dialog orelse return;

    // Scrim at layer 10; card at layer 11.
    {
        const scrim = ui.div(c).fixed().offset(0, 0).w(c.size.w).h(c.size.h).layer(10)
            .bg(.{ .r = 0, .g = 0, .b = 0, .a = 0.55 });
        const hit = scrim.interaction();
        scrim.end();
        if (hit.clicked) s.dialog = null;
    }

    const cw: f32 = 400;
    const x = (c.size.w - cw) / 2;
    const y = (c.size.h - 260) / 2;
    // An explicit height keeps the footer inside the card: a fixed-position
    // column with no height lets its children overflow past `clip()`.

    const card = ui.div(c).fixed().offset(x, y).w(cw).layer(11).column()
        .rounded(12).bg(t.background_100).border(t.alpha_400).borderW(1)
        .shadow(.{ .color = .{ .a = 0.6 }, .blur = 32, .y = 16 }).clip();
    defer card.end();

    {
        const head = ui.div(c).column().wFull().p(24).gap(10);
        defer head.end();
        ui.text(c, d.titleSlice(), .{ .size = 20, .line_height = 26, .weight = .semibold, .color = t.gray_1000 });
        ui.text(c, d.noteSlice(), .{ .size = 14, .line_height = 22, .wrap = true, .color = t.gray_900 });
        if (d.kind == .rename) {
            // The field carries a blue focus ring (design's rename_dialog).
            // itemsCenter keeps the text on the field's middle line rather
            // than against its top edge.
            const field = ui.div(c).row().wFull().h(38).px(12).itemsCenter().rounded(10).bg(t.background_200)
                .border(t.blue_700).borderW(1)
                .shadow(.{ .color = .{ .r = 0.0, .g = 0.44, .b = 0.95, .a = 0.25 }, .blur = 0, .y = 0 });
            defer field.end();
            _ = ui.textField(c, &s.rename_input, .{ .placeholder = "Session name", .bare = true, .width = .fill, .size = 14 });
        }
        if (d.kind == .discard and d.targetSlice().len > 0) {
            const target = ui.div(c).row().wFull().h(36).px(12).gap(10).itemsCenter().rounded(8).bg(t.background_200).border(t.alpha_200).borderW(1);
            defer target.end();
            w.dot(c, t.red_700);
            ui.text(c, d.targetSlice(), .{ .size = 12, .mono = true, .family = t.mono_family, .truncate = .ellipsis, .color = t.gray_900 });
            // The file's +/- totals, like the design's discard_dialog.
            for (s.changes.changes.items) |ch| {
                if (!std.mem.eql(u8, ch.path, d.targetSlice())) continue;
                if (ch.added > 0) ui.text(c, c.print("+{d}", .{ch.added}), .{ .size = 12, .mono = true, .family = t.mono_family, .color = t.green_900 });
                if (ch.removed > 0) ui.text(c, c.print("−{d}", .{ch.removed}), .{ .size = 12, .mono = true, .family = t.mono_family, .color = t.red_900 });
                break;
            }
        }
    }

    {
        const foot = ui.div(c).row().wFull().h(64).px(24).gap(12).itemsCenter().justifyBetween().bg(t.background_200);
        defer foot.end();
        if (w.button(c, "dialog-cancel", "Cancel", false)) s.dialog = null;
        const label: []const u8 = switch (d.kind) {
            .remove => "Remove session",
            .rename => "Rename",
            .full_access => "Switch",
            .discard => "Discard",
        };
        const danger = d.kind == .remove or d.kind == .discard;
        if (w.button(c, "dialog-confirm", label, !danger)) s.pending_dialog_confirm = true;
    }
}
