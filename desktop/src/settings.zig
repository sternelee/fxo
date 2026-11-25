//! Settings shell (⌘,): 200pt section nav + scrollable content, mirroring
//! fx-ui-main/src/views/settings/mod.rs and rows.rs.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const t = @import("tokens.zig");
const w = @import("widgets.zig");
const pages = @import("settings_pages.zig");
const State = @import("state.zig").State;

pub const Section = enum { models, behaviour, mcp, skills, usage, about };

pub const sections = [_]struct { key: Section, label: []const u8 }{
    .{ .key = .models, .label = "Models & accounts" },
    .{ .key = .behaviour, .label = "Behaviour" },
    .{ .key = .mcp, .label = "MCP servers" },
    .{ .key = .skills, .label = "Skills" },
    .{ .key = .usage, .label = "Usage" },
    .{ .key = .about, .label = "About" },
};

pub fn pageTitle(c: *ui.Context, title: []const u8, detail: []const u8) void {
    ui.text(c, title, .{ .size = 22, .line_height = 30, .weight = .medium, .color = t.gray_1000 });
    ui.text(c, detail, .{ .size = 14, .line_height = 20, .wrap = true, .color = t.gray_900 });
}

/// A settings row: title + detail on the left, optional control on the right.
pub fn row(c: *ui.Context, title: []const u8, detail: []const u8) void {
    const r = ui.div(c).row().wFull().px(16).py(14).gap(12).itemsCenter();
    defer r.end();
    const col = ui.div(c).column().grow().gap(2);
    defer col.end();
    ui.text(c, title, .{ .size = 14, .line_height = 20, .color = t.gray_1000 });
    if (detail.len > 0) {
        ui.text(c, detail, .{ .size = 13, .line_height = 18, .wrap = true, .color = t.gray_900 });
    }
}

/// A card of rows separated by hairlines.
pub fn cardStart(c: *ui.Context) ui.Div {
    return ui.div(c).column().wFull().rounded(12).bg(t.gray_100).border(t.alpha_300).borderW(1).clip();
}

pub fn separator(c: *ui.Context) void {
    const s = ui.div(c).wFull().h(1).bg(t.alpha_200);
    s.end();
}

pub fn groupTitle(c: *ui.Context, title: []const u8) void {
    ui.text(c, title, .{ .size = 13, .line_height = 18, .weight = .medium, .color = t.gray_1000 });
}

/// A settings row whose right side is a clickable select: the value plus a
/// chevron. Clicking opens the same popup the composer uses, anchored on the
/// row's own trigger (design's select_row / select_trigger).
pub fn selectRow(c: *ui.Context, id: []const u8, title: []const u8, detail: []const u8, value: []const u8) ?@import("nanoui").ui.Point {
    ui.key(c, id);
    const r = ui.div(c).row().wFull().px(16).py(14).gap(12).itemsCenter().control().hover(t.alpha_100);
    defer r.end();
    {
        const col = ui.div(c).column().grow().gap(2);
        defer col.end();
        ui.text(c, title, .{ .size = 14, .line_height = 20, .color = t.gray_1000 });
        if (detail.len > 0) ui.text(c, detail, .{ .size = 13, .line_height = 18, .wrap = true, .color = t.gray_900 });
    }
    // The trigger: value + chevron, like the design's select_button.
    const trigger = ui.div(c).row().h(26).px(10).gap(6).itemsCenter().rounded(6)
        .bg(t.alpha_100).border(t.alpha_400).borderW(1);
    defer trigger.end();
    ui.text(c, value, .{ .size = 13, .line_height = 18, .color = t.gray_1000 });
    @import("icons.zig").draw(c, "chevron-down", 12, t.gray_900);
    if (!r.clicked()) return null;
    // The anchor is the trigger's bottom-centre, read from last frame's rect.
    if (c.rects.get(trigger.id())) |rect| {
        return .{ .x = rect.x + rect.w / 2, .y = rect.y + rect.h };
    }
    return .{ .x = c.size.w / 2, .y = c.size.h - 200 };
}

/// A toggle switch (34x20), returns true if clicked.
pub fn toggle(c: *ui.Context, id: []const u8, on: bool) bool {
    ui.key(c, id);
    // A 34x20 track with a 16pt knob. One box: the track's own padding places
    // the knob, so no wrapper can collapse its size.
    const track = ui.div(c).row().size(34, 20).p(2).rounded(10).control()
        .bg(if (on) t.blue_700 else t.gray_500)
        .border(if (on) t.blue_700 else t.gray_500).borderW(1);
    defer track.end();
    if (on) {
        const sp = ui.div(c).grow();
        sp.end();
    }
    const knob = ui.div(c).size(16, 16).rounded(8).bg(t.white);
    knob.end();
    if (!on) {
        const sp = ui.div(c).grow();
        sp.end();
    }
    return track.clicked();
}

pub fn view(s: *State, c: *ui.Context) void {
    const root = ui.div(c).row().grow().wFull().itemsStart();
    defer root.end();

    {
        const nav = ui.div(c).column().w(200).hFull().gap(1).px(10).py(16);
        defer nav.end();
        for (sections) |sec| {
            ui.key(c, c.print("settings-{s}", .{sec.label}));
            const on = s.settings_section == sec.key;
            const item = ui.div(c).row().h(30).wFull().px(10).gap(10).itemsCenter().rounded(6)
                .control().bg(if (on) t.alpha_200 else t.background_100).hover(t.alpha_100);
            defer item.end();
            ui.text(c, sec.label, .{ .size = 13, .line_height = 18, .color = if (on) t.gray_1000 else t.gray_900 });
            if (item.clicked()) s.settings_section = sec.key;
        }
    }

    {
        const body = ui.div(c).column().grow().hFull().scrollY().px(40).py(36);
        defer body.end();
        const inner = ui.div(c).column().wFull().maxW(640).gap(32);
        defer inner.end();
        switch (s.settings_section) {
            .models => pages.models(s, c),
            .behaviour => pages.behaviour(s, c),
            .mcp => pages.mcp(s, c),
            .skills => pages.skills(s, c),
            .usage => pages.usage(s, c),
            .about => pages.about(s, c),
        }
    }
}
