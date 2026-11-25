//! Tab bar shown when the sidebar is collapsed, mirroring shell.rs render_tabs.
const std = @import("std");
const ui = @import("nanoui").ui;
const t = @import("tokens.zig");
const w = @import("widgets.zig");
const State = @import("state.zig").State;

pub fn view(s: *State, c: *ui.Context) void {
    // On macOS the traffic lights sit at x=20/40/60 in this 48pt bar. The
    // design's render_tabs reserves pl(92) so the first control clears them;
    // other platforms have no window buttons and keep the tight 12pt inset.
    const left: f32 = if (@import("builtin").os.tag == .macos) 92 else 12;
    const bar = ui.div(c).row().h(48).wFull().pl(left).pr(12).gap(8).itemsCenter().bg(t.background_200);
    defer bar.end();

    if (w.iconButton(c, "tab-sidebar", "panel-left")) s.sidebar_open = true;

    // Folder switcher: the current workspace's name + chevron, opening a menu
    // of every workspace (design's folders_button).
    {
        ui.key(c, "folders");
        const name = if (s.workspaces.items.len > 0) s.workspaces.items[s.folder].name else "No folder";
        const open = s.folders_menu_open;
        const btn = ui.div(c).row().h(28).px(8).gap(6).itemsCenter().rounded(8).control()
            .bg(if (open) t.alpha_200 else t.background_200).hover(t.alpha_200);
        defer btn.end();
        ui.text(c, name, .{ .size = 13, .line_height = 18, .truncate = .ellipsis, .color = t.gray_900 });
        @import("icons.zig").draw(c, "chevron-down", 12, t.gray_700);
        if (btn.clicked()) s.folders_menu_open = !s.folders_menu_open;
    }

    const divider0 = ui.div(c).w(1).h(16).bg(t.alpha_300);
    divider0.end();

    // New session: plus icon + label, on the same row as the expand button.
    ui.key(c, "tab-new");
    const new_btn = ui.div(c).row().h(30).px(10).gap(8).itemsCenter().rounded(6)
        .control().hover(t.alpha_200);
    defer new_btn.end();
    @import("icons.zig").draw(c, "plus", 14, t.gray_1000);
    ui.text(c, "New session", .{ .size = 13, .line_height = 18, .color = t.gray_1000 });
    if (new_btn.clicked()) s.newSession();

    const divider = ui.div(c).w(1).h(16).bg(t.alpha_300);
    divider.end();

    {
        const tabs = ui.div(c).row().grow().gap(2).itemsCenter();
        defer tabs.end();
        if (s.workspaces.items.len > 0) {
            const ws = &s.workspaces.items[s.folder];
            var shown: usize = 0;
            for (ws.sessions.items, 0..) |session, i| {
                if (shown >= 6) break;
                ui.key(c, c.print("tab-{d}", .{i}));
                const on = s.page == .session and s.active == i;
                const tab = ui.div(c).row().h(30).maxW(150).px(10).gap(8).itemsCenter().rounded(8)
                    .control().bg(if (on) t.alpha_200 else t.background_200).hover(t.alpha_100);
                defer tab.end();
                w.dot(c, if (session.status == .running) t.blue_700 else t.gray_500);
                ui.text(c, session.title, .{ .size = 13, .line_height = 18, .truncate = .ellipsis, .color = if (on) t.gray_1000 else t.gray_900 });
                if (tab.clicked()) s.selectSession(i);
                shown += 1;
            }
        }
    }

    if (w.iconButton(c, "tab-search", "search")) s.palette.open = true;
    if (w.iconButton(c, "tab-settings", "settings")) s.page = .settings;
    {
        // The account avatar shows the user's initial, like the sidebar.
        const avatar = ui.div(c).size(24, 24).rounded(12).bg(t.gray_300).center();
        defer avatar.end();
        const name = @import("sidebar.zig").userName();
        const initial: []const u8 = if (name.len > 0) name[0..1] else "f";
        ui.text(c, initial, .{ .size = 11, .weight = .semibold, .color = t.gray_1000 });
    }
}

/// The folder switcher's menu: one row per workspace, plus Add folder
/// (design's folders_menu).
pub fn foldersMenu(s: *State, c: *ui.Context) void {
    if (!s.folders_menu_open) return;

    {
        const scrim = ui.div(c).fixed().offset(0, 0).w(c.size.w).h(c.size.h).layer(20);
        const hit = scrim.interaction();
        scrim.end();
        if (hit.clicked) {
            s.folders_menu_open = false;
            return;
        }
    }

    const card = ui.div(c).fixed().offset(12, 60).w(240).layer(21).column().p(6)
        .rounded(12).bg(t.gray_100).border(t.alpha_400).borderW(1)
        .shadow(.{ .color = .{ .a = 0.6 }, .blur = 24, .y = 10 }).clip();
    defer card.end();

    for (s.workspaces.items, 0..) |ws, i| {
        ui.key(c, c.print("folder-{d}", .{i}));
        const on = i == s.folder;
        const row = ui.div(c).row().wFull().h(30).px(8).gap(10).itemsCenter().rounded(6)
            .control().bg(if (on) t.alpha_200 else t.gray_100).hover(t.alpha_200);
        defer row.end();
        @import("icons.zig").draw(c, "folder", 14, t.gray_900);
        ui.text(c, ws.name, .{ .size = 13, .line_height = 18, .truncate = .ellipsis, .color = t.gray_1000 });
        {
            const spacer = ui.div(c).grow();
            defer spacer.end();
        }
        if (on) @import("icons.zig").draw(c, "check", 14, t.gray_900);
        if (row.clicked()) {
            s.folder = i;
            s.active = null;
            s.page = .home;
            s.folders_menu_open = false;
        }
    }
    {
        const sep = ui.div(c).wFull().h(1).bg(t.alpha_200);
        sep.end();
    }
    if (w.nav(c, "folder-add", "plus", "Add folder", "⌘O", false)) {
        s.folders_menu_open = false;
        s.openFolderDialog();
    }
}
