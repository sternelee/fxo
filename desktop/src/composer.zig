//! Composer: text field + toolbar pills + send button + @ / / picker popup.
const std = @import("std");
const ui = @import("nanoui").ui;
const t = @import("tokens.zig");
const w = @import("widgets.zig");
const State = @import("state.zig").State;

/// Bottom-center of a box from its last laid-out rect; used to anchor menus.
fn anchorOf(c: *ui.Context, id: u64) @import("nanoui").ui.Point {
    if (c.rects.get(id)) |r| {
        return .{ .x = r.x + r.w / 2, .y = r.y + r.h };
    }
    return .{ .x = c.size.w / 2, .y = c.size.h - 40 };
}

fn pickerPopup(s: *State, c: *ui.Context) void {
    if (s.picker.count == 0) return;
    const p = &s.picker;
    const skills = p.kind == .skill;
    const width: f32 = if (skills) 520 else 460;
    const popup = ui.div(c).column().w(width).maxW(c.size.w - 80).p(6).rounded(12)
        .bg(t.background_100).border(t.alpha_400).borderW(1)
        .shadow(.{ .color = .{ .a = 0.6 }, .blur = 24, .y = 12 });
    defer popup.end();

    // Heading names the workspace for files, like the design's picker_heading.
    {
        const heading = if (skills)
            "Skills"
        else if (s.workspaces.items.len > 0)
            c.print("Files in {s}", .{s.workspaces.items[s.folder].name})
        else
            "Files";
        ui.text(c, heading, .{ .size = 12, .line_height = 16, .weight = .medium, .color = t.gray_900 });
    }
    for (p.items[0..p.count], 0..) |*item, i| {
        ui.key(c, c.print("pick-{d}", .{i}));
        const on = i == p.selected;
        const row = ui.div(c).row().wFull().h(if (skills) 44 else 36).px(8).gap(if (skills) 12 else 10).itemsCenter()
            .rounded(6).control().bg(if (on) t.alpha_200 else t.background_100).hover(t.alpha_100);
        defer row.end();
        if (row.clicked()) {
            p.selected = i;
            s.acceptPicker();
        }
        if (skills) {
            // A skill row: a fixed 112pt name column, then its description.
            const name_box = ui.div(c).row().w(112).itemsCenter();
            defer name_box.end();
            ui.text(c, item.labelSlice(), .{ .size = 13, .line_height = 20, .truncate = .ellipsis, .color = t.gray_1000 });
            ui.text(c, item.detailSlice(), .{ .size = 13, .line_height = 18, .truncate = .ellipsis, .color = t.gray_900 });
        } else {
            @import("icons.zig").draw(c, "file", 14, if (on) t.gray_1000 else t.gray_900);
            ui.text(c, item.labelSlice(), .{ .size = 13, .line_height = 20, .mono = true, .family = t.mono_family, .color = t.gray_1000 });
            {
                const spacer = ui.div(c).grow();
                defer spacer.end();
            }
            ui.text(c, item.detailSlice(), .{ .size = 12, .line_height = 16, .truncate = .ellipsis, .color = t.gray_700 });
        }
    }
    // Footer: skills show the count, files show the key hints.
    {
        const foot = ui.div(c).row().wFull().h(32).px(8).gap(16).itemsCenter();
        defer foot.end();
        if (skills) {
            ui.text(c, "⏎ Use skill", .{ .size = 12, .line_height = 16, .color = t.gray_900 });
            {
                const spacer = ui.div(c).grow();
                defer spacer.end();
            }
            ui.text(c, c.print("{d} skill{s}", .{ p.count, if (p.count == 1) "" else "s" }), w.faint(12, 16));
        } else {
            ui.text(c, "⏎ Attach", .{ .size = 12, .line_height = 16, .color = t.gray_900 });
            ui.text(c, "Tab Complete path", .{ .size = 12, .line_height = 16, .color = t.gray_900 });
        }
    }
}

/// A thinking-level indicator: four bars of increasing height, the first
/// `lit` of them in the active colour (design's bars()).
fn thinkingBars(c: *ui.Context, lit: usize) void {
    const box = ui.div(c).row().size(14, 14).itemsEnd().justifyBetween();
    defer box.end();
    const heights = [_]f32{ 4, 7, 10, 13 };
    for (heights, 0..) |h, i| {
        const bar = ui.div(c).w(2.5).h(h).rounded(0.75)
            .bg(if (i < lit) t.gray_900 else t.gray_500);
        bar.end();
    }
}

/// The thinking level's label and bar count, from fx's effort value.
fn thinkingLevel(effort: []const u8) struct { lit: usize, label: []const u8 } {
    if (std.mem.eql(u8, effort, "none")) return .{ .lit = 0, .label = "Off" };
    if (std.mem.eql(u8, effort, "minimal")) return .{ .lit = 1, .label = "Minimal" };
    if (std.mem.eql(u8, effort, "low")) return .{ .lit = 1, .label = "Low" };
    if (std.mem.eql(u8, effort, "medium")) return .{ .lit = 2, .label = "Medium" };
    if (std.mem.eql(u8, effort, "high")) return .{ .lit = 3, .label = "High" };
    if (std.mem.eql(u8, effort, "xhigh")) return .{ .lit = 4, .label = "Max" };
    return .{ .lit = 2, .label = "Auto" };
}

/// A usage ring: a grey track with an arc for the fraction used, amber past
/// 80% (design's ring()).
fn usageRing(c: *ui.Context, fraction: f32) void {
    const cv = ui.canvas(c, .{ .width = .{ .px = 18 }, .height = .{ .px = 18 } });
    const center = ui.Point{ .x = 9, .y = 9 };
    const r: f32 = 6.3;
    cv.ring(center, r, 1.8, t.gray_400);
    const f = @max(0.02, @min(0.999, fraction));
    // The arc as a short polyline: 24 segments is smooth at this size.
    var pts: [25]ui.Point = undefined;
    const segs: usize = 24;
    const total = f * std.math.tau;
    for (0..segs + 1) |i| {
        const a = total * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segs));
        pts[i] = .{ .x = center.x + r * @sin(a), .y = center.y - r * @cos(a) };
    }
    cv.polyline(pts[0 .. segs + 1], .{ .width = 1.8, .color = if (f > 0.8) t.amber_700 else t.gray_900 });
}

pub fn view(s: *State, c: *ui.Context) void {
    const root = ui.div(c).column().wFull().gap(6);
    defer root.end();

    // Picker and pill menus sit above the composer card.
    pickerPopup(s, c);

    // Attached image thumbnails, 56pt with a remove button on hover.
    if (s.attachments.items.len > 0) {
        const strip = ui.div(c).row().wFull().gap(8).pb(4);
        defer strip.end();
        for (s.attachments.items, 0..) |bytes, i| {
            ui.key(c, c.print("shot-{d}", .{i}));
            const thumb = ui.div(c).size(56, 56).rounded(10).control();
            defer thumb.end();
            _ = ui.image(c, .{ .key = c.print("attach-{d}", .{i}), .bytes = bytes, .box = .{ .w = 56, .h = 56 }, .radius = 10 });
            if (thumb.clicked()) {
                _ = s.attachments.orderedRemove(i);
                break;
            }
        }
    }

    // Queued prompts: shown above the card as "Next" / "Then" rows
    // (design's queued_row).
    if (s.currentSession()) |session| {
        if (session.queue.items.len > 0) {
            const dock = ui.div(c).column().wFull().gap(2).pb(4);
            defer dock.end();
            for (session.queue.items, 0..) |said, i| {
                ui.key(c, c.print("queued-{d}", .{i}));
                const row = ui.div(c).row().wFull().h(30).px(10).gap(10).itemsCenter().rounded(8).control().hover(t.alpha_100);
                defer row.end();
                ui.text(c, if (i == 0) "Next" else "Then", .{ .size = 12, .line_height = 16, .color = t.gray_700 });
                ui.text(c, said, .{ .size = 13, .line_height = 18, .truncate = .ellipsis, .color = t.gray_1000 });
                {
                    const spacer = ui.div(c).grow();
                    defer spacer.end();
                }
                ui.key(c, c.print("queued-remove-{d}", .{i}));
                const x = ui.div(c).size(20, 20).rounded(5).control().center().hover(t.alpha_300);
                defer x.end();
                @import("icons.zig").draw(c, "x", 12, t.gray_900);
                if (x.clicked()) s.dropQueued(i);
            }
        }
    }

    // The attach menu: mention a file, choose images, or paste one
    // (design's attach_menu). It floats above the composer card.
    if (s.attach_menu) {
        const at = @import("composer_menu.zig").popupOrigin(s.menu_anchor, 220, 130, c.size.w, c.size.h);
        const pop = ui.div(c).fixed().offset(at.x, at.y).w(220).p(6).rounded(12).layer(12)
            .bg(t.background_100).border(t.alpha_400).borderW(1)
            .shadow(.{ .color = .{ .a = 0.6 }, .blur = 24, .y = 12 }).clip();
        defer pop.end();
        if (@import("sidebar.zig").menuItem(c, "attach-file", "file", "Mention a file", "@", false)) {
            s.attach_menu = false;
            s.input.set("@");
            s.updatePicker();
        }
        if (@import("sidebar.zig").menuItem(c, "attach-choose", "image", "Choose images…", "", false)) {
            s.attach_menu = false;
            const picked = @import("nanoui").dialog.open(s.alloc, .{
                .title = "Attach images",
                .files = true,
                .directories = false,
                .multiple = true,
                .extensions = &.{ "png", "jpg", "jpeg", "gif", "webp" },
            }) catch null;
            defer if (picked) |paths| @import("nanoui").dialog.freePaths(s.alloc, paths);
            if (picked) |paths| s.attachImages(paths);
        }
        if (@import("sidebar.zig").menuItem(c, "attach-paste", "copy", "Paste image", "⌘V", false)) {
            s.attach_menu = false;
            s.status_line = "Paste an image with ⌘V";
        }
    }

    // The card: 20pt radius, padding that tightens when thumbnails are shown,
    // and a click anywhere focuses the field (design's composer_card).
    const pad_top: f32 = if (s.attachments.items.len == 0) 14 else 10;
    const card = ui.div(c).column().wFull().pt(pad_top).px(10).pb(10).gap(8).rounded(20)
        .bg(t.gray_100).border(t.alpha_400).borderW(1)
        .shadow(.{ .color = .{ .a = 0.5 }, .blur = 24, .y = 8 }).control();
    defer card.end();
    if (card.clicked()) s.input.focus();

    const field = ui.textField(c, &s.input, .{
        .placeholder = "Reply to fx, or type @ for files and / for skills",
        .width = .fill,
        .size = 14,
        .bare = true,
        .multiline = true,
        .max_lines = 8,
        .line_height = 20,
        .color = t.gray_1000,
        .placeholder_color = t.gray_700,
    });
    if (field.changed) s.updatePicker();

    const toolbar = ui.div(c).row().wFull().gap(4).itemsCenter();
    defer toolbar.end();
    const icons = @import("icons.zig");
    // Attach pill: plus icon in a 32pt circle (design uses plus-lg).
    {
        ui.key(c, "attach");
        const attach = ui.div(c).size(28, 28).rounded(6).control().center().hover(t.alpha_200);
        defer attach.end();
        icons.draw(c, "plus-lg", 16, t.gray_900);
        if (attach.clicked()) {
            s.menu_anchor = anchorOf(c, attach.id());
            s.attach_menu = !s.attach_menu;
        }
    }
    // Mode pill: shield icon + capitalized label.
    const raw_mode = if (s.fx_info.permission_mode.slice().len > 0) s.fx_info.permission_mode.slice() else "auto";
    const mode_label: []const u8 = if (std.mem.eql(u8, raw_mode, "ask")) "Ask" else if (std.mem.eql(u8, raw_mode, "full-access")) "Full access" else "Auto";
    {
        ui.key(c, "mode-pill");
        const mp = ui.div(c).row().itemsCenter().h(32).px(12).gap(6).rounded(16).control()
            .border(t.alpha_400).borderW(1).hover(t.alpha_200);
        defer mp.end();
        icons.draw(c, "shield", 14, t.gray_1000);
        ui.text(c, mode_label, w.textStyle(13, 18));
        if (mp.clicked()) {
            s.menu_anchor = anchorOf(c, mp.id());
            s.composer_menu = if (s.composer_menu == .mode) null else .mode;
        }
    }
    {
        const spacer = ui.div(c).grow();
        defer spacer.end();
    }
    // Model pill with chevron-down, as in the design.
    const model_label = if (s.fx_info.model.slice().len > 0) @import("fxcli.zig").modelName(c.alloc(), s.fx_info.model.slice()) else "Default";
    {
        ui.key(c, "model-pill");
        const model_pill = ui.div(c).row().itemsCenter().h(32).px(10).gap(6).rounded(16).control().hover(t.alpha_200);
        defer model_pill.end();
        ui.text(c, model_label, w.textStyle(13, 18));
        icons.draw(c, "chevron-down", 12, t.gray_900);
        if (model_pill.clicked()) {
            s.menu_anchor = anchorOf(c, model_pill.id());
            s.composer_menu = if (s.composer_menu == .model) null else .model;
        }
    }
    // Thinking pill: bars + label, opening the thinking menu.
    {
        ui.key(c, "thinking-pill");
        const lv = thinkingLevel(s.fx_info.effort.slice());
        const tp = ui.div(c).row().itemsCenter().h(32).px(10).gap(7).rounded(16).control().hover(t.alpha_200);
        defer tp.end();
        thinkingBars(c, lv.lit);
        ui.text(c, lv.label, .{ .size = 13, .line_height = 18, .color = t.gray_900 });
        if (s.fast_mode) icons.draw(c, "bolt", 12, t.gray_900);
        if (tp.clicked()) {
            s.menu_anchor = anchorOf(c, tp.id());
            s.composer_menu = if (s.composer_menu == .thinking) null else .thinking;
        }
    }
    // The workspace's branch, so a new session says what it will commit to
    // (design's branch_label, shown on the home composer).
    if (s.page == .home and s.workspaces.items.len > 0) {
        const branch = s.changes.branch;
        if (branch.len > 0 and !std.mem.eql(u8, branch, "HEAD")) {
            const bl = ui.div(c).row().h(32).px(10).gap(6).itemsCenter();
            defer bl.end();
            icons.draw(c, "branch", 14, t.gray_900);
            ui.text(c, branch, .{ .size = 12, .line_height = 16, .mono = true, .family = t.mono_family, .color = t.gray_900 });
        }
    }
    // Usage ring pill (opens the usage menu) + Fast mode toggle.
    {
        ui.key(c, "usage-pill");
        const up = ui.div(c).size(32, 32).rounded(16).control().center().hover(t.alpha_200);
        defer up.end();
        // The ring shows spend against the plan's cap when fx reports one.
        const spend = s.fx_info.spend;
        const fraction: f32 = if (spend > 0) @floatCast(@min(1.0, spend / 10.0)) else 0.02;
        usageRing(c, fraction);
        if (up.clicked()) {
            s.menu_anchor = anchorOf(c, up.id());
            s.composer_menu = if (s.composer_menu == .usage) null else .usage;
        }
    }
    if (@import("settings.zig").toggle(c, "composer-fast", s.fast_mode)) {
        s.fast_mode = !s.fast_mode;
        State.setConfigDefault("fast_mode", if (s.fast_mode) "true" else "false");
    }

    // The send/stop button: stop only while running with nothing drafted;
    // a drafted prompt sends (and queues) even mid-turn.
    const running = if (s.currentSession()) |session| session.status == .running else false;
    const drafted = std.mem.trim(u8, s.input.text(), " \t\r\n").len > 0 or s.attachments.items.len > 0;
    const show_stop = running and !drafted;
    ui.key(c, if (show_stop) "stop" else "send");
    const send = ui.div(c).size(32, 32).rounded(16).control().center()
        .bg(t.gray_1000).hover(t.white);
    defer send.end();
    if (show_stop) {
        // A 10pt rounded square, like the design's stop mark.
        const stop = ui.div(c).size(10, 10).rounded(2).bg(t.background_100);
        stop.end();
    } else {
        @import("icons.zig").draw(c, "arrow-up", 16, t.background_100);
    }
    if (send.clicked() or field.submitted) s.sendPrompt();
}
