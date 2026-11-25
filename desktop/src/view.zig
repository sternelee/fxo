//! Root view: sidebar + main panel, with the design's fixed widths.
const std = @import("std");
const ui = @import("nanoui").ui;
const t = @import("tokens.zig");
pub const State = @import("state.zig").State;
const sidebar = @import("sidebar.zig");
const home = @import("home.zig");
const thread_view = @import("thread.zig");
const composer = @import("composer.zig");
const permission = @import("permission.zig");
const palette_mod = @import("palette.zig");
const changes_view = @import("changes.zig");
const settings_view = @import("settings.zig");
const dialog_view = @import("dialog.zig");
const engine_mod = @import("engine.zig");
const w = @import("widgets.zig");

/// Callback from the permission card. Copies the option id into state memory
/// because the snapshot buffer dies with this frame.
fn answerCallback(s: *State, option: ?[]const u8) void {
    const id = s.answer_id orelse return;
    var opt_copy: ?[]const u8 = null;
    if (option) |o| {
        const n = @min(s.answer_buf.len, o.len);
        @memcpy(s.answer_buf[0..n], o[0..n]);
        opt_copy = s.answer_buf[0..n];
    }
    s.pending_answer = .{ .id = id, .option = opt_copy };
}

pub fn view(s: *State, c: *ui.Context) void {
    c.theme_chosen = if (s.light_theme) ui.Theme.light else ui.Theme.dark_theme;
    c.title_bar_height = 48; // keeps macOS traffic lights in the sidebar header

    // Advance elapsed time on the running turn so the Working row can show it.
    if (s.currentSession()) |session| {
        if (session.turns.items.len > 0) {
            const last = &session.turns.items[session.turns.items.len - 1];
            if (last.status == .running) {
                last.elapsed_ms += @intFromFloat(@max(0, c.dt) * 1000);
                c.animationFrame(); // keep the spinner ticking
            }
        }
    }

    // Merge worker snapshot into UI state when a new revision landed.
    var snap: engine_mod.Snapshot = .{ .alloc = s.alloc };
    defer snap.deinit(s.alloc);
    if (s.engine) |engine| {
        engine.read(&snap);
        if (snap.revision != s.last_revision) {
            s.last_revision = snap.revision;
            s.agent_error = snap.err_msg;
            s.status_line = snap.status;
            if (snap.permission) |perm| {
                s.answer_id = perm.request_id;
                s.status_line = "Waiting for approval";
            }
            if (s.currentSession()) |session| {
                if (session.turns.items.len > 0) {
                    const last = &session.turns.items[session.turns.items.len - 1];
                    last.answer.clearRetainingCapacity();
                    last.answer.appendSlice(s.alloc, snap.agent_text.items) catch {};
                    last.thought.clearRetainingCapacity();
                    last.thought.appendSlice(s.alloc, snap.thought_text.items) catch {};
                    last.steps = snap.steps;
                    last.step_count = snap.step_count;
                    // fx names the session once it knows the turn's subject;
                    // take that name unless the user renamed it themselves.
                    if (snap.title.len > 0 and !session.renamed and
                        !std.mem.eql(u8, session.title, snap.title))
                    {
                        const owned = s.alloc.dupe(u8, snap.title) catch null;
                        if (owned) |name| {
                            s.alloc.free(session.title);
                            session.title = name;
                        }
                    }
                    if (snap.status.len > 0 and !std.mem.eql(u8, snap.status, "working") and !std.mem.eql(u8, snap.status, "waiting")) {
                        last.status = .idle;
                        session.status = .idle;
                        // Record why it stopped, when fx said so.
                        if (snap.stop_reason.len > 0) last.stop_reason = snap.stop_reason;
                        // A queued prompt goes out now that the turn settled.
                        s.flushQueue();
                    } else if (std.mem.eql(u8, snap.status, "waiting")) {
                        session.status = .waiting;
                    }
                }
            }
        }
    }

    // Merge fx CLI snapshot for Settings when the loader published a revision.
    if (s.fx_loader) |loader| {
        var info: @import("fxcli.zig").Info = .{};
        loader.read(&info);
        if (info.revision != s.fx_info.revision) s.fx_info = info;
    }

    // A preview permission (tests/snapshots) takes precedence over the worker.
    const active_perm: ?*const engine_mod.Permission = if (s.preview_permission) |*pp|
        pp
    else if (snap.permission) |*sp|
        sp
    else
        null;

    // The composer picker owns arrow/enter/escape while it has matches.
    if (s.picker.count > 0) {
        const pc = s.picker.count;
        if (c.shortcut(.{ .key = ui.Shortcut.down })) {
            s.picker.selected = (s.picker.selected + 1) % pc;
        } else if (c.shortcut(.{ .key = ui.Shortcut.up })) {
            s.picker.selected = if (s.picker.selected == 0) pc - 1 else s.picker.selected - 1;
        } else if (c.shortcut(.{ .key = ui.Shortcut.enter })) {
            s.acceptPicker();
        } else if (c.shortcut(.{ .key = ui.Shortcut.escape })) {
            s.picker = .{};
        }
    }

    // A dialog takes over keys: Enter confirms, Esc cancels.
    if (s.dialog != null) {
        if (c.shortcut(.{ .key = ui.Shortcut.enter })) s.pending_dialog_confirm = true;
        if (c.shortcut(.{ .key = ui.Shortcut.escape })) s.dialog = null;
    }

    // The palette owns the keys while open (⌘K toggles it).
    if (s.dialog == null) palette_mod.Palette.handleKeys(s, &s.palette, c);

    // A permission request takes over the keys: Enter allows, Esc denies.
    // An open palette has already consumed these keys above.
    if (active_perm) |perm| {
        s.answer_id = perm.request_id;
        if (s.preview_permission != null) s.status_line = "Waiting for approval";
        if (!s.palette.open) {
            if (c.shortcut(.{ .key = ui.Shortcut.enter }) or c.shortcut(.{ .key = ui.Shortcut.enter, .cmd = true })) {
                if (perm.defaultAllow()) |o| {
                    const n = @min(s.answer_buf.len, o.idSlice().len);
                    @memcpy(s.answer_buf[0..n], o.idSlice()[0..n]);
                    s.pending_answer = .{ .id = perm.request_id, .option = s.answer_buf[0..n] };
                }
            } else if (c.shortcut(.{ .key = ui.Shortcut.escape })) {
                s.pending_answer = .{ .id = perm.request_id, .option = null };
            }
        }
    } else if (!s.palette.open) {
        if (c.shortcut(.{ .key = 'n', .cmd = true })) s.newSession();
        if (c.shortcut(.{ .key = 'b', .cmd = true })) s.sidebar_open = !s.sidebar_open;
        if (c.shortcut(.{ .key = '\\', .cmd = true })) s.toggleChanges();
        if (c.shortcut(.{ .key = 'o', .cmd = true })) s.openFolderDialog();
        if (c.shortcut(.{ .key = ',', .cmd = true })) {
            s.page = if (s.page == .settings) .home else .settings;
        }
        if (c.shortcut(.{ .key = ui.Shortcut.escape })) {
            if (s.composer_menu != null) {
                s.composer_menu = null;
            } else {
                s.page = .home;
                s.active = null;
            }
        }
    }

    const root = ui.div(c).row().sizeFull().bg(t.background_100);
    defer root.end();
    if (s.sidebar_open) sidebar.view(s, c);
    // The session row's ⋯ menu floats above the sidebar.
    if (s.row_menu != null) sidebar.rowMenu(s, c);
    // The tab bar's folder switcher menu.
    if (s.folders_menu_open) @import("tabbar.zig").foldersMenu(s, c);

    const changes_w: f32 = if (s.changes_open) 400 else 0;
    const beside_w: f32 = if (s.beside != null) @import("beside.zig").width else 0;
    const main_w = c.size.w - (if (s.sidebar_open) t.sidebar_width else 0) - changes_w - beside_w;
    {
        const main = ui.div(c).column().w(main_w).hFull();
        defer main.end();

        // With the sidebar collapsed, the tab bar replaces the header entirely
        // (design: render_tabs is the alternate form of render_header). This
        // keeps the expand button and New session on the same 48pt row.
        if (!s.sidebar_open) {
            @import("tabbar.zig").view(s, c);
        } else {
            const header = ui.div(c).row().h(44).wFull().pl(20).pr(10).gap(8).itemsCenter();
            defer header.end();
            const icons = @import("icons.zig");
            if (s.page == .settings) {
                ui.text(c, "Settings", w.muted(13, 18));
            } else if (s.workspaces.items.len == 0) {
                ui.text(c, "Welcome", w.muted(13, 18));
            } else {
                const ws = &s.workspaces.items[s.folder];
                const session_opt = if (s.page == .session) s.currentSession() else null;
                if (session_opt) |session| {
                    // Breadcrumb: workspace › session (medium weight, truncated).
                    // It takes the free width so the pills stay on one line.
                    const crumb = ui.div(c).row().grow().gap(6).itemsCenter();
                    defer crumb.end();
                    ui.text(c, ws.name, .{ .size = 13, .line_height = 18, .truncate = .ellipsis, .color = t.gray_900 });
                    icons.draw(c, "chevron-right", 12, t.gray_600);
                    ui.text(c, session.title, .{ .size = 13, .line_height = 18, .weight = .medium, .truncate = .ellipsis, .color = t.gray_1000 });
                } else {
                    ui.text(c, if (s.page == .home) "New session" else ws.name, w.muted(13, 18));
                    const hspacer0 = ui.div(c).grow();
                    defer hspacer0.end();
                }
                // Branch pill (from git snapshot).
                if (s.changes.branch.len > 0 and !std.mem.eql(u8, s.changes.branch, "HEAD")) {
                    const branch = ui.div(c).row().h(28).px(10).gap(6).itemsCenter().rounded(6);
                    defer branch.end();
                    icons.draw(c, "branch", 14, t.gray_900);
                    ui.text(c, s.changes.branch, .{ .size = 12, .mono = true, .family = t.mono_family, .color = t.gray_900 });
                }
                // Changes toggle with +/- stats (mirrors shell.rs changes_toggle).
                const totals = s.changes.totals();
                const ct = ui.div(c).row().h(28).px(10).gap(6).itemsCenter().rounded(6).control().border(t.alpha_400).borderW(1).hover(t.alpha_200);
                defer ct.end();
                if (s.changes.changes.items.len == 0) {
                    ui.text(c, "No changes", .{ .size = 12, .color = t.gray_900 });
                } else {
                    if (totals.added > 0) ui.text(c, c.print("+{d}", .{totals.added}), .{ .size = 12, .mono = true, .family = t.mono_family, .color = t.green_900 });
                    if (totals.removed > 0) ui.text(c, c.print("−{d}", .{totals.removed}), .{ .size = 12, .mono = true, .family = t.mono_family, .color = t.red_900 });
                }
                if (ct.clicked()) s.toggleChanges();
                // Overflow menu button.
                if (w.iconButton(c, "header-menu", "ellipsis")) s.palette.open = true;
            }
        }

        if (s.agent_error != null and s.page != .home) {
            // Outside home the error stays a compact strip; home shows the
            // full recovery card instead.
            const err = s.agent_error.?;
            const error_box = ui.div(c).row().px(16).py(10).wFull().rounded(12).bg(t.gray_100).border(t.alpha_400).borderW(1);
            defer error_box.end();
            ui.text(c, err, .{ .size = 13, .line_height = 18, .wrap = true, .color = t.red_900 });
        }

        if (s.page == .home) {
            home.view(s, c);
        } else if (s.page == .settings) {
            settings_view.view(s, c);
        } else {
            thread_view.view(s, c);
            if (active_perm) |perm| {
                const card_box = ui.div(c).column().wFull().px(40).pb(8);
                defer card_box.end();
                const cb = struct {
                    fn call(cx: *anyopaque, option: ?[]const u8) void {
                        answerCallback(@ptrCast(@alignCast(cx)), option);
                    }
                }.call;
                permission.view(perm, c, s, cb);
            }
            const composer_box = ui.div(c).column().wFull().px(40).pb(24);
            defer composer_box.end();
            composer.view(s, c);
        }
    }

    // Changes panel docks beside the main content.
    if (s.changes_open) changes_view.view(s, c);
    // The beside pane shows a second session, dimmed and click-to-swap.
    if (s.beside != null) @import("beside.zig").view(s, c);

    // Pill menus render above the page so both the composer and the settings
    // select rows can open them.
    @import("composer_menu.zig").view(s, c);

    // Overlay sits above everything, in its own layers.
    palette_mod.Palette.overlay(s, &s.palette, c);
    // Dialog is the topmost layer.
    dialog_view.view(s, c);

    // Deliver the answer after the frame: the writer lives on the worker.
    if (s.pending_answer) |answer| {
        s.pending_answer = null;
        s.answer_id = null;
        s.answers_sent += 1;
        if (s.engine) |engine| {
            engine.answer(answer.id, answer.option);
            engine.clearPermission();
        } else {
            // No worker in tests/snapshots: clear the preview card.
            s.preview_permission = null;
        }
    }

    if (s.pending_dialog_confirm) {
        s.pending_dialog_confirm = false;
        s.confirmDialog();
    }

    // Apply the palette's action after the frame (it closes during drawing).
    if (s.pending_action) |action| {
        s.pending_action = null;
        switch (action) {
            .new_session => s.newSession(),
            .toggle_sidebar => s.sidebar_open = !s.sidebar_open,
            .open_folder => s.openFolderDialog(),
            .attach_images => {
                const picked = @import("nanoui").dialog.open(s.alloc, .{
                    .title = "Attach images",
                    .files = true,
                    .directories = false,
                    .multiple = true,
                    .extensions = &.{ "png", "jpg", "jpeg", "gif", "webp" },
                }) catch null;
                defer if (picked) |paths| @import("nanoui").dialog.freePaths(s.alloc, paths);
                if (picked) |paths| s.attachImages(paths);
            },
            .toggle_changes => s.toggleChanges(),
            .open_settings => s.page = if (s.page == .settings) .home else .settings,
            .rename_session => s.openRename(),
            .remove_session => s.openRemove(),
            .stop_turn => {
                if (s.engine) |engine| engine.cancel();
                if (s.currentSession()) |session| {
                    session.status = .idle;
                    for (session.turns.items) |*turn| turn.status = .idle;
                }
                s.status_line = "Stopped";
            },
            .open_session => |i| s.selectSession(i),
        }
    }
}
