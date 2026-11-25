//! Composer pill dropdowns (mode / model / thinking / usage), mirroring
//! fx-ui-main/src/views/composer/{menus,models,usage}.rs.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const t = @import("tokens.zig");
const w = @import("widgets.zig");
const State = @import("state.zig").State;

pub const Menu = enum { mode, model, thinking, usage };

/// Popup top-left: horizontally centered on the anchor pill, just above it,
/// clamped inside the window. Pure so the anchoring can be tested.
pub fn popupOrigin(anchor: @import("nanoui").ui.Point, popup_w: f32, popup_h: f32, win_w: f32, win_h: f32) @import("nanoui").ui.Point {
    var px = anchor.x - popup_w / 2;
    px = @max(8, @min(px, win_w - popup_w - 8));
    var py = anchor.y - 8 - popup_h;
    py = @max(8, @min(py, win_h - popup_h - 8));
    return .{ .x = px, .y = py };
}

pub fn view(s: *State, c: *ui.Context) void {
    const menu = s.composer_menu orelse return;
    const width: f32 = switch (menu) {
        .mode => 300,
        .model => 320,
        .thinking => 340,
        .usage => 300,
    };
    // Fixed overlay anchored above the composer: it takes no layout space, so
    // opening the menu never moves the input field (design: deferred + absolute).
    const popup_h: f32 = switch (menu) {
        .mode => 190,
        // The model menu lists up to 12 rows plus a search field and footer.
        .model => 520,
        .thinking => 280,
        .usage => 200,
    };
    const popup_w = width;
    const at = popupOrigin(s.menu_anchor, popup_w, popup_h, c.size.w, c.size.h);
    const px = at.x;
    const py = at.y;
    const popup = ui.div(c).column().fixed().offset(px, py).w(popup_w).maxW(c.size.w - 80)
        .maxH(c.size.h - 24).p(6).rounded(12).layer(12)
        .bg(t.gray_100).border(t.alpha_400).borderW(1)
        .shadow(.{ .color = .{ .a = 0.6 }, .blur = 24, .y = 12 });
    defer popup.end();

    switch (menu) {
        .mode => modeMenu(s, c),
        .model => modelMenu(s, c),
        .thinking => thinkingMenu(s, c),
        .usage => usageMenu(s, c),
    }
}

fn menuRow(c: *ui.Context, id: []const u8, label: []const u8, detail: []const u8, on: bool) bool {
    ui.key(c, id);
    const row = ui.div(c).row().wFull().h(48).px(10).gap(10).itemsCenter().rounded(8)
        .control().bg(if (on) t.alpha_200 else t.gray_100).hover(t.alpha_200);
    defer row.end();
    {
        // Scoped so the check icon below is a sibling of this column, not a
        // child of it (a defer here would run after the icon is drawn).
        const col = ui.div(c).column().grow().gap(2);
        defer col.end();
        ui.text(c, label, .{ .size = 13, .line_height = 18, .weight = .medium, .color = t.gray_1000 });
        if (detail.len > 0) ui.text(c, detail, .{ .size = 12, .line_height = 16, .color = t.gray_900 });
    }
    // Check sits at the row's right edge, vertically centered.
    if (on) @import("icons.zig").draw(c, "check", 14, t.gray_1000);
    return row.clicked();
}

fn modeMenu(s: *State, c: *ui.Context) void {
    ui.text(c, "Permission mode", .{ .size = 12, .line_height = 16, .color = t.gray_700 });
    const info = &s.fx_info;
    if (info.mode_count == 0) {
        ui.text(c, "No modes reported", w.faint(12, 16));
        ui.text(c, "fx status lists what this build offers", w.faint(12, 16));
        return;
    }
    // The modes fx itself reports, with its own labels and descriptions.
    for (info.modes[0..info.mode_count], 0..) |m, i| {
        const on = std.mem.eql(u8, info.permission_mode.slice(), m.id.slice());
        if (menuRow(c, c.print("mode-{d}", .{i}), m.name.slice(), m.description.slice(), on)) {
            if (std.mem.eql(u8, m.id.slice(), "full-access")) {
                var d = @import("dialog.zig").Dialog{ .kind = .full_access };
                d.setTitle("Switch to Full access?");
                d.setNote("fx runs every edit and command in this session without asking. You can switch back at any time.");
                s.dialog = d;
            } else {
                info.permission_mode.set(m.id.slice());
                if (s.engine) |engine| engine.setConfigOption("mode", m.id.slice());
            }
            s.composer_menu = null;
        }
    }
    // Grants approved in this session (design's "Allowed in this session").
    if (info.session_grants > 0) {
        const sep = ui.div(c).wFull().h(1).bg(t.alpha_400);
        sep.end();
        const head = ui.div(c).row().wFull().px(8).py(6).itemsCenter();
        defer head.end();
        ui.text(c, "Allowed in this session", .{ .size = 12, .line_height = 16, .weight = .medium, .color = t.gray_900 });
        {
            const spacer = ui.div(c).grow();
            defer spacer.end();
        }
        ui.text(c, c.print("{d}", .{info.session_grants}), w.faint(12, 16));
    }
}

fn modelMenu(s: *State, c: *ui.Context) void {
    const info = &s.fx_info;
    const current = info.model.slice();
    const query = std.mem.trim(u8, s.model_query.text(), " \t");

    // A search field, like the design's model_search_row.
    {
        const box = ui.div(c).row().wFull().h(30).px(8).gap(8).itemsCenter().rounded(6).bg(t.background_200);
        defer box.end();
        @import("icons.zig").draw(c, "search", 14, t.gray_900);
        _ = ui.textField(c, &s.model_query, .{ .placeholder = "Search models", .bare = true, .width = .fill, .size = 13 });
    }

    var shown: usize = 0;
    var matches: usize = 0;
    {
        // The list scrolls inside a bounded box so a long catalog cannot
        // push the footer off the window.
        const list = ui.div(c).column().wFull().maxH(300).scrollY().gap(1);
        defer list.end();
        var last_account: []const u8 = "";
        for (info.catalog[0..info.catalog_count]) |id| {
            const name = id.slice();
            if (query.len > 0 and std.mem.indexOf(u8, name, query) == null) continue;
            matches += 1;
            if (shown >= 12) continue;
            // Models group under their account, which is the id's prefix
            // (design's account_heading).
            const account = accountOf(name);
            if (!std.mem.eql(u8, account, last_account)) {
                // A heading separates accounts; only the first needs no gap.
                if (shown > 0) {
                    const sp = ui.div(c).h(6).end();
                    _ = sp;
                }
                const head = ui.div(c).row().wFull().h(24).px(8).itemsCenter();
                defer head.end();
                ui.text(c, account, .{ .size = 12, .line_height = 16, .weight = .medium, .color = t.gray_900 });
                last_account = account;
            }
            const label = @import("fxcli.zig").modelName(c.alloc(), name);
            const on = std.mem.eql(u8, name, current);
            if (menuRow(c, c.print("model-{d}", .{shown}), label, name, on)) {
                if (s.engine) |engine| engine.setConfigOption("model", name);
                info.model.set(name);
                s.composer_menu = null;
            }
            shown += 1;
        }
        if (info.catalog_count == 0) {
            ui.text(c, "No model catalog", w.faint(12, 16));
            ui.text(c, "fx models lists what this account can use", w.faint(12, 16));
        } else if (matches == 0) {
            ui.text(c, "Nothing matches", w.faint(12, 16));
        }
    }

    // Footer: the count, then the key hints (design's model_footer).
    {
        const foot = ui.div(c).row().wFull().h(28).px(8).gap(8).itemsCenter();
        defer foot.end();
        const count_label = if (query.len == 0)
            c.print("{d} model{s}", .{ info.catalog_count, if (info.catalog_count == 1) "" else "s" })
        else
            c.print("{d} of {d}", .{ matches, info.catalog_count });
        ui.text(c, count_label, w.faint(12, 16));
        {
            const spacer = ui.div(c).grow();
            defer spacer.end();
        }
        ui.text(c, "⏎ Use", .{ .size = 12, .color = t.gray_900 });
    }
}

/// The account a model id belongs to: its prefix before the first slash.
fn accountOf(id: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, id, '/')) |at| return id[0..at];
    return "Models";
}

fn thinkingMenu(s: *State, c: *ui.Context) void {
    ui.text(c, "Thinking", .{ .size = 12, .line_height = 16, .color = t.gray_700 });
    const levels = [_]struct { label: []const u8, value: []const u8 }{
        .{ .label = "Default", .value = "auto" },
        .{ .label = "Off", .value = "none" },
        .{ .label = "Minimal", .value = "minimal" },
        .{ .label = "Low", .value = "low" },
        .{ .label = "Medium", .value = "medium" },
        .{ .label = "High", .value = "high" },
        .{ .label = "Max", .value = "xhigh" },
    };
    for (levels, 0..) |level, i| {
        // The current effort is the one fx reports; "auto" is the default.
        const current = s.fx_info.effort.slice();
        const on = if (current.len == 0)
            i == 0
        else
            std.mem.eql(u8, current, level.value);
        if (menuRow(c, c.print("think-{d}", .{i}), level.label, "", on)) {
            if (s.engine) |engine| engine.setConfigOption("effort", level.value);
            s.fx_info.effort.set(level.value);
            s.composer_menu = null;
        }
    }
}

fn usageMenu(s: *State, c: *ui.Context) void {
    const info = &s.fx_info;
    ui.text(c, "Usage", .{ .size = 13, .line_height = 18, .weight = .medium, .color = t.gray_1000 });
    if (!info.loaded) {
        ui.text(c, "Loading…", w.faint(12, 16));
        return;
    }
    ui.text(c, if (info.usage_source.slice().len > 0) info.usage_source.slice() else "Your provider", w.faint(12, 16));
    gap(c, 8);
    // Meters for this period's spend, requests and tokens. The bars are
    // relative to a fixed reference because fx reports no budget for this
    // provider (budget is null in `fx usage --json`), so the note says what
    // the number is rather than pretending a plan cap.
    const period = s.usage_period;
    const period_label: []const u8 = if (std.mem.eql(u8, period, "today"))
        "today"
    else if (std.mem.eql(u8, period, "7d"))
        "in the last 7 days"
    else
        "this month";
    meter(c, "Spend", c.print("${d:.2}", .{info.spend}), @as(f32, @floatCast(@min(1.0, info.spend / 10.0))), period_label);
    meter(c, "Requests", c.print("{d:.0}", .{info.request_count}), @as(f32, @floatCast(@min(1.0, info.request_count / 100.0))), period_label);
    meter(c, "Tokens", c.print("{d:.0}", .{info.total_tokens}), @as(f32, @floatCast(@min(1.0, info.total_tokens / 100000.0))), period_label);
    if (info.usage_status.slice().len > 0 and !std.mem.eql(u8, info.usage_status.slice(), "ok")) {
        gap(c, 6);
        ui.text(c, c.print("Status: {s} {s}", .{ info.usage_status.slice(), info.usage_reason.slice() }), .{ .size = 12, .color = t.amber_700 });
    }
}

/// A usage meter: label + value, a 4pt bar, and a note line under it
/// (design's meter). Past 80% the value and bar turn amber.
fn meter(c: *ui.Context, label: []const u8, value: []const u8, fraction: f32, note: []const u8) void {
    const warn = fraction > 0.8;
    const box = ui.div(c).column().wFull().gap(6).px(10).py(6);
    defer box.end();
    {
        const row = ui.div(c).row().wFull().gap(8).itemsCenter();
        defer row.end();
        ui.text(c, label, .{ .size = 13, .line_height = 20, .weight = .medium, .color = t.gray_1000 });
        {
            const spacer = ui.div(c).grow();
            defer spacer.end();
        }
        ui.text(c, value, .{ .size = 12, .mono = true, .family = t.mono_family, .color = if (warn) t.amber_700 else t.gray_900 });
    }
    const track = ui.div(c).wFull().h(4).rounded(2).bg(t.gray_300);
    defer track.end();
    const fill = ui.div(c).hFull().w(@max(2, 260 * @min(1.0, @max(0.01, fraction)))).rounded(2)
        .bg(if (warn) t.amber_700 else t.gray_1000);
    fill.end();
    if (note.len > 0) ui.text(c, note, .{ .size = 12, .line_height = 16, .color = t.gray_700 });
}

fn gap(c: *ui.Context, amount: f32) void {
    ui.div(c).h(amount).end();
}
