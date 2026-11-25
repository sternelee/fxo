//! The beside pane: a second session shown next to the main one, dimmed and
//! click-to-swap. Mirrors fx-ui-main/src/views/thread/mod.rs render_beside.
const std = @import("std");
const ui = @import("nanoui").ui;
const t = @import("tokens.zig");
const w = @import("widgets.zig");
const State = @import("state.zig").State;

pub const width: f32 = 320;

pub fn view(s: *State, c: *ui.Context) void {
    const at = s.beside orelse return;
    if (at.ws >= s.workspaces.items.len) {
        s.beside = null;
        return;
    }
    const ws = &s.workspaces.items[at.ws];
    if (at.si >= ws.sessions.items.len) {
        s.beside = null;
        return;
    }
    const session = &ws.sessions.items[at.si];

    const panel = ui.div(c).column().w(width).hFull().bg(t.background_100)
        .border(t.alpha_400).borderW(1);
    defer panel.end();

    // The header: the session's title, a status mark, and a close button.
    {
        const head = ui.div(c).row().h(44).wFull().pl(20).pr(10).gap(8).itemsCenter();
        defer head.end();
        ui.text(c, session.title, .{ .size = 13, .line_height = 18, .truncate = .ellipsis, .color = t.gray_900 });
        {
            const spacer = ui.div(c).grow();
            defer spacer.end();
        }
        if (session.status == .running) {
            w.spinner(c, "beside-spin", t.gray_900);
        } else if (session.status == .waiting) {
            w.dot(c, t.amber_700);
        }
        if (w.iconButton(c, "beside-close", "x")) s.beside = null;
    }

    // The body is dimmed: clicking it swaps this session into the main pane.
    {
        const body = ui.div(c).column().grow().wFull().scrollY().px(16).pt(12).pb(24).control();
        defer body.end();
        if (session.turns.items.len == 0) {
            ui.text(c, "Nothing here yet", w.faint(13, 18));
        } else {
            // The last few turns, newest last, so the pane reads like a thread.
            const start = if (session.turns.items.len > 3) session.turns.items.len - 3 else 0;
            for (session.turns.items[start..]) |turn| {
                {
                    const bubble = ui.div(c).column().wFull().px(12).py(8).rounded(14).bg(t.gray_200);
                    defer bubble.end();
                    ui.text(c, turn.prompt, .{ .size = 13, .line_height = 20, .wrap = true, .color = t.gray_1000 });
                }
                if (turn.answer.items.len > 0) {
                    ui.text(c, turn.answer.items, .{ .size = 13, .line_height = 20, .wrap = true, .color = t.gray_900 });
                }
            }
        }
        if (session.status == .waiting) {
            ui.text(c, "Waiting on your answer. Click to work in this one.", .{ .size = 13, .line_height = 18, .color = t.amber_700 });
        }
        if (body.clicked()) s.swapBeside();
    }
}
