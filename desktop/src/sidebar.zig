//! Sidebar: 248pt wide, fx mark + nav + workspace/session groups + account row.
const std = @import("std");
const ui = @import("nanoui").ui;
const t = @import("tokens.zig");
const w = @import("widgets.zig");
const State = @import("state.zig").State;

pub fn view(s: *State, c: *ui.Context) void {
    const root = ui.div(c).column().w(t.sidebar_width).hFull().px(8).pb(8).bg(t.background_200);
    defer root.end();

    {
        const header = ui.div(c).row().h(48).wFull().itemsCenter().pl(80).pr(4).gap(8);
        defer header.end();
        ui.text(c, "fx", .{ .size = 16, .weight = .bold, .color = t.gray_1000 });
        const spacer = ui.div(c).grow();
        defer spacer.end();
        if (w.iconButton(c, "sidebar-toggle", "panel-left")) s.sidebar_open = false;
    }

    {
        const nav = ui.div(c).column().gap(1).pt(4).wFull();
        defer nav.end();
        if (w.nav(c, "new", "compose", "New session", "⌘N", false)) s.newSession();
        if (w.nav(c, "search", "search", "Search", "⌘K", false)) {}
        if (w.nav(c, "skills", "star", "Skills", "", s.page == .settings and s.settings_section == .skills)) {
            s.page = .settings;
            s.settings_section = .skills;
        }
    }

    {
        const list = ui.div(c).column().grow().wFull().scrollY().gap(1).pt(20);
        defer list.end();
        for (s.workspaces.items, 0..) |ws, wi| {
            const group = ui.div(c).column().gap(1).pt(if (wi == 0) 0 else 16).wFull();
            defer group.end();
            {
                const head = ui.div(c).row().h(26).px(8).gap(6).itemsCenter().wFull();
                defer head.end();
                // The name takes the slack so the + stays at the right edge
                // (design's ws_head).
                {
                    const col = ui.div(c).column().grow().gap(0);
                    defer col.end();
                    ui.text(c, ws.name, w.textStyle(12, 16));
                }
                ui.key(c, c.print("new-in-{d}", .{wi}));
                const plus = ui.div(c).size(18, 18).rounded(4).control().center().hover(t.alpha_300);
                defer plus.end();
                @import("icons.zig").draw(c, "plus", 14, t.gray_700);
                if (plus.clicked()) s.newSessionIn(wi);
            }
            const recent: usize = 5;
            const shown = if (s.show_all_sessions) ws.sessions.items.len else @min(recent, ws.sessions.items.len);
            for (ws.sessions.items[0..shown], 0..) |session, si| {
                ui.key(c, c.print("session-{d}-{d}", .{ wi, si }));
                const active = s.page == .session and s.folder == wi and s.active == si;
                const menu_open = if (s.row_menu) |m| m.ws == wi and m.si == si else false;
                const row = ui.div(c).row().h(30).wFull().px(8).gap(10).itemsCenter()
                    .rounded(6).control()
                    .bg(if (active or menu_open) t.alpha_200 else t.background_200).hover(t.alpha_200);
                defer row.end();
                const status_color: ui.Color = switch (session.status) {
                    .idle => t.gray_500,
                    .waiting => t.amber_700,
                    .running => t.blue_700,
                    .stopped => t.red_700,
                };
                w.dot(c, status_color);
                ui.text(c, session.title, .{ .size = 13, .line_height = 18, .truncate = .ellipsis, .color = t.gray_1000 });
                {
                    const spacer = ui.div(c).grow();
                    defer spacer.end();
                }
                // The trailing slot holds one thing at a time: the ⋯ button,
                // which opens the row menu. (The age lives on the home list.)
                ui.key(c, c.print("row-menu-{d}-{d}", .{ wi, si }));
                const dots = ui.div(c).size(20, 20).rounded(5).control().center()
                    .bg(if (menu_open) t.alpha_300 else t.background_200).hover(t.alpha_300);
                defer dots.end();
                @import("icons.zig").draw(c, "ellipsis", 14, t.gray_1000);
                if (dots.clicked()) {
                    s.row_menu = if (menu_open) null else .{ .ws = wi, .si = si };
                }
                if (row.clicked()) s.selectSession(si);
            }
            if (ws.sessions.items.len > recent) {
                ui.key(c, "show-more");
                const more = ui.div(c).row().h(30).wFull().px(8).itemsCenter().rounded(6).control().hover(t.alpha_100);
                defer more.end();
                const label = if (s.show_all_sessions)
                    "Show fewer"
                else
                    c.print("Show {d} more", .{ws.sessions.items.len - recent});
                ui.text(c, label, .{ .size = 13, .line_height = 18, .color = t.gray_700 });
                if (more.clicked()) s.show_all_sessions = !s.show_all_sessions;
            }
        }
        ui.key(c, "add-folder");
        const add = ui.div(c).row().h(30).wFull().px(8).gap(8).itemsCenter().rounded(6).control().hover(t.alpha_200);
        defer add.end();
        ui.text(c, "Add folder", w.faint(13, 18));
        const aspacer = ui.div(c).grow();
        defer aspacer.end();
        ui.text(c, "⌘O", w.faint(12, 16));
        // The row is the button: it opens the folder picker, as the tab bar's
        // Add folder does.
        if (add.clicked()) s.openFolderDialog();
    }

    {
        const account = ui.div(c).row().h(44).wFull().px(8).gap(10).itemsCenter();
        defer account.end();
        const name = userName();
        const initial: []const u8 = if (name.len > 0) name[0..1] else "f";
        {
            const avatar = ui.div(c).size(24, 24).rounded(12).bg(t.gray_300).center();
            defer avatar.end();
            ui.text(c, initial, .{ .size = 11, .weight = .semibold, .color = t.gray_1000 });
        }
        {
            // A fixed-width column keeps the two lines stacked beside the
            // avatar instead of spilling past the sidebar.
            const info = ui.div(c).column().w(140).gap(1);
            defer info.end();
            ui.text(c, name, .{ .size = 13, .line_height = 18, .truncate = .ellipsis, .color = t.gray_1000 });
            const provider = if (s.fx_info.provider_count > 0)
                s.fx_info.providers[0].slice()
            else
                "fx";
            ui.text(c, provider, .{ .size = 12, .line_height = 16, .truncate = .ellipsis, .color = t.gray_700 });
        }
        {
            const spacer = ui.div(c).grow();
            defer spacer.end();
        }
        // Theme toggle (sun icon); cycles the app's dark/light choice.
        if (w.iconButton(c, "theme-toggle", "sun")) {
            s.light_theme = !s.light_theme;
        }
    }
}

/// First name from `id -F`, falling back to $USER then "You", like the design.
pub fn userName() []const u8 {
    const io = @import("proc.zig").io();
    const argv = [_][]const u8{ "id", "-F" };
    if (std.process.run(std.heap.c_allocator, io, .{ .argv = &argv })) |r| {
        defer std.heap.c_allocator.free(r.stderr);
        defer std.heap.c_allocator.free(r.stdout);
        const full = std.mem.trim(u8, r.stdout, " \t\r\n");
        if (full.len > 0) {
            if (std.mem.indexOfAny(u8, full, " \t")) |at| return firstTokenStatic(full[0..at]);
            return firstTokenStatic(full);
        }
    } else |_| {}
    return "You";
}

/// The session row's ⋯ menu: Rename / Show changes / Copy session id /
/// Remove from list (design's menu_card).
pub fn rowMenu(s: *State, c: *ui.Context) void {
    const m = s.row_menu orelse return;
    if (m.ws >= s.workspaces.items.len) {
        s.row_menu = null;
        return;
    }
    const ws = &s.workspaces.items[m.ws];
    if (m.si >= ws.sessions.items.len) {
        s.row_menu = null;
        return;
    }
    const session = &ws.sessions.items[m.si];

    // A scrim closes the menu on any outside click.
    {
        const scrim = ui.div(c).fixed().offset(0, 0).w(c.size.w).h(c.size.h).layer(20);
        const hit = scrim.interaction();
        scrim.end();
        if (hit.clicked) {
            s.row_menu = null;
            return;
        }
    }

    const card = ui.div(c).fixed().offset(12, 120).w(220).layer(21).column().p(6)
        .rounded(12).bg(t.gray_100).border(t.alpha_400).borderW(1)
        .shadow(.{ .color = .{ .a = 0.6 }, .blur = 24, .y = 10 }).clip();
    defer card.end();

    if (menuItem(c, "menu-rename", "pencil", "Rename", "", false)) {
        s.active = m.si;
        s.page = .session;
        s.row_menu = null;
        s.openRename();
        return;
    }
    if (menuItem(c, "menu-changes", "panel-right", "Show changes", "⌘\\", false)) {
        s.active = m.si;
        s.page = .session;
        s.row_menu = null;
        s.changes_open = true;
        return;
    }
    // "Open beside" only makes sense for a session that is not already active.
    const already_active = s.page == .session and s.folder == m.ws and s.active == m.si;
    if (!already_active) {
        if (menuItem(c, "menu-beside", "panel-split", "Open beside", "", false)) {
            s.row_menu = null;
            s.openBeside(m.ws, m.si);
            return;
        }
    }
    if (session.id) |id| {
        if (menuItem(c, "menu-copy", "copy", "Copy session id", "", false)) {
            c.clipboard.write(c.clipboard.ctx, id);
            s.row_menu = null;
            return;
        }
    }
    {
        const sep = ui.div(c).wFull().h(1).bg(t.alpha_200);
        sep.end();
    }
    // The destructive item is red, icon and label (design's menu_item
    // danger flag).
    if (menuItem(c, "menu-remove", "trash", "Remove from list", "", true)) {
        s.active = m.si;
        s.page = .session;
        s.row_menu = null;
        s.openRemove();
        return;
    }
}

pub fn menuItem(c: *ui.Context, id: []const u8, icon_name: []const u8, label: []const u8, keys: []const u8, danger: bool) bool {
    ui.key(c, id);
    const box = ui.div(c).row().wFull().h(30).px(8).gap(10).itemsCenter().rounded(6).control().hover(t.alpha_200);
    defer box.end();
    const color = if (danger) t.red_900 else t.gray_1000;
    @import("icons.zig").draw(c, icon_name, 14, color);
    ui.text(c, label, .{ .size = 13, .line_height = 18, .color = color });
    {
        const spacer = ui.div(c).grow();
        defer spacer.end();
    }
    if (keys.len > 0) ui.text(c, keys, w.faint(12, 16));
    return box.clicked();
}

fn firstTokenStatic(s: []const u8) []const u8 {
    const copy = std.heap.c_allocator.dupe(u8, s) catch return "You";
    return copy;
}
