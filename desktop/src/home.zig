//! Home: hero, composer, and the Recent/Running/Archived session lists.
//! Mirrors fx-ui-main/src/views/home.rs.
const std = @import("std");
const ui = @import("nanoui").ui;
const t = @import("tokens.zig");
const w = @import("widgets.zig");
const composer = @import("composer.zig");
const State = @import("state.zig").State;
const Session = @import("state.zig").Session;
const art = @import("art.zig");

pub const HomeTab = enum { recent, running, archived };

fn tabButton(c: *ui.Context, id: []const u8, label: []const u8, count: usize, target: HomeTab, s: *State) void {
    ui.key(c, id);
    const on = s.home_tab == target;
    const btn = ui.div(c).row().h(26).px(8).gap(6).itemsCenter().rounded(6)
        .control().bg(if (on) t.alpha_200 else t.background_100).hover(t.alpha_100);
    defer btn.end();
    ui.text(c, label, .{ .size = 13, .line_height = 18, .weight = if (on) .medium else .regular, .color = if (on) t.gray_1000 else t.gray_900 });
    if (count > 0) ui.text(c, c.print("{d}", .{count}), .{ .size = 12, .mono = true, .family = t.mono_family, .color = t.gray_700 });
    if (btn.clicked()) s.home_tab = target;
}

fn tabs(c: *ui.Context, s: *State, live: usize, archived: usize) void {
    const bar = ui.div(c).row().wFull().h(28).px(2).gap(4).itemsCenter();
    defer bar.end();
    tabButton(c, "tab-recent", "Recent", 0, .recent, s);
    tabButton(c, "tab-running", "Running", live, .running, s);
    tabButton(c, "tab-archived", "Archived", archived, .archived, s);
    {
        const spacer = ui.div(c).grow();
        defer spacer.end();
    }
    if (w.button(c, "all-sessions", "All sessions  ⌘K", false)) s.palette.open = true;
}

fn emptyList(c: *ui.Context, tab: HomeTab) void {
    const msg: []const u8 = switch (tab) {
        .running => "Nothing is running\nSessions that are working show up here.",
        .archived => "Nothing archived\nSessions you remove from the list are kept here.",
        .recent => "No sessions yet\nYour first prompt starts one.",
    };
    const box = ui.div(c).column().wFull().itemsCenter().gap(6).py(36);
    defer box.end();
    var lines = std.mem.splitScalar(u8, msg, '\n');
    if (lines.next()) |title| ui.text(c, title, w.textStyle(14, 20));
    if (lines.next()) |detail| ui.text(c, detail, w.faint(13, 18));
}

/// A day heading above a group of rows (design's day_heading).
fn dayHeading(c: *ui.Context, name: []const u8, first: bool) void {
    const box = ui.div(c).row().wFull().h(if (first) 32 else 36).px(10).itemsCenter();
    defer box.end();
    ui.text(c, name, .{ .size = 12, .line_height = 16, .color = t.gray_700 });
}

/// One session row: status mark, title, optional note, right-aligned age
/// (design's list_row).
fn listRow(c: *ui.Context, id: []const u8, session: *const Session, note: ?[]const u8, note_color: ui.Color) bool {
    ui.key(c, id);
    const row = ui.div(c).row().h(34).wFull().px(10).gap(10).rounded(8).control().hover(t.alpha_100);
    defer row.end();
    if (session.status == .running) {
        w.spinner(c, c.print("{s}-spin", .{id}), t.blue_700);
    } else {
        w.dot(c, t.gray_500);
    }
    ui.text(c, session.title, .{ .size = 14, .line_height = 20, .truncate = .ellipsis, .color = t.gray_1000 });
    {
        const spacer = ui.div(c).grow();
        defer spacer.end();
    }
    if (note) |n| {
        if (n.len > 0) ui.text(c, n, .{ .size = 12, .line_height = 16, .truncate = .ellipsis, .color = note_color });
    }
    // Fixed-width right-aligned age, so titles line up across rows.
    const age_box = ui.div(c).row().w(28).justifyEnd();
    defer age_box.end();
    ui.text(c, session.age(c), .{ .size = 12, .line_height = 16, .color = t.gray_700 });
    return row.clicked();
}

/// The note column: what a running turn is doing, else the session's diff
/// totals (design's recent_row).
fn noteFor(s: *State, c: *ui.Context, session: *const Session) struct { text: []const u8, color: ui.Color } {
    if (session.status == .running) {
        if (session.turns.items.len > 0) {
            const last = &session.turns.items[session.turns.items.len - 1];
            if (last.status == .running and last.step_count > 0) {
                const step = &last.steps[last.step_count - 1];
                const detail = step.detailSlice();
                if (detail.len > 0) return .{ .text = detail, .color = t.gray_900 };
                const name = step.nameSlice();
                if (name.len > 0) return .{ .text = name, .color = t.gray_900 };
            }
        }
        return .{ .text = "working", .color = t.gray_900 };
    }
    _ = s;
    _ = c;
    return .{ .text = "", .color = t.gray_700 };
}

/// A pending approval for a session, shown above the lists so the user can
/// answer without opening the session (design's approval_card).
fn approvalCard(s: *State, c: *ui.Context, perm: *const @import("engine.zig").Permission) void {
    const card = ui.div(c).row().wFull().gap(10).pl(10).pr(12).py(12).rounded(12)
        .bg(t.gray_100).border(t.alpha_300).borderW(1).control();
    defer card.end();

    w.dot(c, t.amber_700);
    {
        const col = ui.div(c).column().grow().gap(2);
        defer col.end();
        const session_title = if (s.currentSession()) |session| session.title else "Session";
        ui.text(c, session_title, .{ .size = 14, .line_height = 20, .weight = .medium, .truncate = .ellipsis, .color = t.gray_1000 });
        {
            const line = ui.div(c).row().gap(8).itemsCenter();
            defer line.end();
            ui.text(c, perm.questionSlice(), .{ .size = 13, .line_height = 18, .color = t.gray_900 });
            {
                // The detail takes the slack so the counts keep their width.
                const mid = ui.div(c).row().grow().gap(8).itemsCenter();
                defer mid.end();
                ui.text(c, perm.detailSlice(), .{ .size = 12, .line_height = 16, .mono = true, .family = t.mono_family, .truncate = .ellipsis, .color = t.gray_700 });
                // The edit's size, so the card says how much is at stake
                // (design's stat in approval_card). It keeps its width so a
                // long detail cannot push the counts out of the row.
                if (perm.diff_count > 0) {
                    const stat = ui.div(c).row().gap(6).itemsCenter();
                    defer stat.end();
                    if (perm.diff_added > 0) ui.text(c, c.print("+{d}", .{perm.diff_added}), .{ .size = 12, .line_height = 16, .mono = true, .family = t.mono_family, .color = t.green_900 });
                    if (perm.diff_removed > 0) ui.text(c, c.print("-{d}", .{perm.diff_removed}), .{ .size = 12, .line_height = 16, .mono = true, .family = t.mono_family, .color = t.red_700 });
                }
            }
        }
    }
    {
        const actions = ui.div(c).row().gap(6).itemsCenter();
        defer actions.end();
        const reject = perm.byKind("reject_once") orelse perm.byKind("reject_always");
        if (w.button(c, "home-deny", "Deny", false)) {
            s.pending_answer = .{ .id = perm.request_id, .option = if (reject) |r| r.idSlice() else null };
        }
        if (perm.byKind("allow_once")) |allow| {
            const label: []const u8 = if (perm.isExecute()) "Run" else "Allow";
            if (w.button(c, "home-allow", label, true)) {
                s.pending_answer = .{ .id = perm.request_id, .option = allow.idSlice() };
            }
        }
    }
}

/// The install page: fx is not on PATH, so show the command to install it
/// (design's render_install).
const install_command = "curl -fsSL https://fx.sh/setup.sh | bash";

fn installPage(s: *State, c: *ui.Context) void {
    const card = ui.div(c).column().wFull().maxW(520).gap(16).p(18).rounded(14)
        .bg(t.gray_100).border(t.alpha_400).borderW(1);
    defer card.end();

    {
        const head = ui.div(c).column().gap(6);
        defer head.end();
        {
            const line = ui.div(c).row().gap(10).itemsCenter();
            defer line.end();
            w.dot(c, t.amber_700);
            ui.text(c, "fx is not installed", .{ .size = 14, .line_height = 20, .weight = .medium, .color = t.gray_1000 });
        }
        ui.text(c, "This app drives the fx command-line tool. Run this in Terminal, sign in with fx login, then start again.", .{ .size = 13, .line_height = 20, .wrap = true, .color = t.gray_900 });
    }
    {
        const box = ui.div(c).row().wFull().px(12).py(10).rounded(8).bg(t.background_200);
        defer box.end();
        ui.text(c, install_command, .{ .size = 12, .line_height = 18, .mono = true, .family = t.mono_family, .color = t.gray_1000 });
    }
    {
        const actions = ui.div(c).row().wFull().gap(8).itemsCenter();
        defer actions.end();
        if (w.button(c, "install-restart", "Start again", true)) {
            s.agent_error = null;
            s.status_line = "Starting fx";
        }
        if (w.button(c, "copy-install", "Copy command", false)) {
            c.clipboard.write(c.clipboard.ctx, install_command);
            s.status_line = "Install command copied";
        }
        {
            const spacer = ui.div(c).grow();
            defer spacer.end();
        }
        ui.text(c, "fx.sh/docs", .{ .size = 13, .line_height = 18, .color = t.gray_900 });
    }
}

/// The first-run page: no workspace yet, so offer the two setup steps
/// (design's render_first_run).
fn firstRunPage(s: *State, c: *ui.Context) void {
    art.view(c, 10);
    ui.text(c, "Welcome to fx", .{ .size = 28, .line_height = 36, .weight = .medium, .color = t.gray_1000 });

    const card = ui.div(c).column().wFull().maxW(520).rounded(14)
        .bg(t.gray_100).border(t.alpha_300).borderW(1).clip();
    defer card.end();

    // Step 1: open a folder.
    {
        const row = ui.div(c).row().wFull().gap(14).px(16).py(16).itemsCenter();
        defer row.end();
        {
            const tile = ui.div(c).size(32, 32).rounded(8).bg(t.gray_200).border(t.alpha_300).borderW(1).center();
            defer tile.end();
            @import("icons.zig").draw(c, "folder", 16, t.gray_1000);
        }
        {
            const col = ui.div(c).column().grow().gap(2);
            defer col.end();
            ui.text(c, "Open a folder", .{ .size = 14, .line_height = 20, .color = t.gray_1000 });
            ui.text(c, "fx only reads, edits and runs inside it", .{ .size = 13, .line_height = 18, .color = t.gray_900 });
        }
        if (w.button(c, "first-choose", "Choose…  ⌘O", true)) s.openFolderDialog();
    }
    {
        const sep = ui.div(c).wFull().h(1).bg(t.alpha_200);
        sep.end();
    }
    // Step 2: connect a model.
    {
        const row = ui.div(c).row().wFull().gap(14).px(16).py(16).itemsCenter();
        defer row.end();
        {
            const tile = ui.div(c).size(32, 32).rounded(8).bg(t.gray_200).border(t.alpha_300).borderW(1).center();
            defer tile.end();
            @import("icons.zig").draw(c, "user", 16, t.gray_1000);
        }
        {
            const col = ui.div(c).column().grow().gap(2);
            defer col.end();
            ui.text(c, "Connect a model", .{ .size = 14, .line_height = 20, .color = t.gray_1000 });
            ui.text(c, "Codex, Grok, or an AI Gateway key", .{ .size = 13, .line_height = 18, .color = t.gray_900 });
        }
        if (w.button(c, "first-connect", "Connect", false)) {
            s.page = .settings;
            s.settings_section = .models;
        }
    }
}

/// The agent-down page: the error's last lines, a heading that tells a
/// signed-out fx from a crash, and the three ways out (design's
/// render_agent_down).
fn agentDown(s: *State, c: *ui.Context, err: []const u8) void {
    const signed_out = std.mem.indexOf(u8, err, "fx login") != null;
    const mark: ui.Color = if (signed_out) t.amber_700 else t.red_700;
    const title: []const u8 = if (signed_out) "No account connected" else "fx acp exited";
    const detail: []const u8 = if (signed_out)
        "fx needs a signed-in account before it can start. Connect one, then start fx again."
    else
        "Your sessions are safe on disk. Start it again, or check what fx needs.";

    const card = ui.div(c).column().wFull().maxW(520).gap(16).p(18).rounded(14)
        .bg(t.gray_100).border(t.alpha_400).borderW(1);
    defer card.end();

    {
        const head = ui.div(c).column().gap(6);
        defer head.end();
        {
            const line = ui.div(c).row().gap(10).itemsCenter();
            defer line.end();
            w.dot(c, mark);
            ui.text(c, title, .{ .size = 14, .line_height = 20, .weight = .medium, .color = t.gray_1000 });
        }
        ui.text(c, detail, .{ .size = 13, .line_height = 20, .wrap = true, .color = t.gray_900 });
    }

    // The last four non-empty lines of the error, in a mono block.
    {
        var lines: [4][]const u8 = undefined;
        var n: usize = 0;
        var it = std.mem.splitScalar(u8, err, '\n');
        while (it.next()) |raw| {
            const line = std.mem.trim(u8, raw, " \t\r");
            if (line.len == 0) continue;
            if (n < lines.len) {
                lines[n] = line;
                n += 1;
            } else {
                var j: usize = 0;
                while (j + 1 < lines.len) : (j += 1) lines[j] = lines[j + 1];
                lines[lines.len - 1] = line;
            }
        }
        if (n > 0) {
            const box = ui.div(c).column().wFull().px(12).py(10).rounded(8).bg(t.background_200);
            defer box.end();
            for (lines[0..n]) |line| {
                ui.text(c, line, .{ .size = 12, .line_height = 18, .mono = true, .family = t.mono_family, .truncate = .ellipsis, .color = t.gray_900 });
            }
        }
    }

    {
        const actions = ui.div(c).row().wFull().gap(8).itemsCenter();
        defer actions.end();
        if (w.button(c, "restart-agent", "Start fx again", true)) {
            s.agent_error = null;
            s.status_line = "Starting fx";
        }
        if (w.button(c, "fix-signin", "Fix sign-in", false)) {
            s.page = .settings;
            s.settings_section = .models;
        }
        {
            const spacer = ui.div(c).grow();
            defer spacer.end();
        }
        if (w.button(c, "run-doctor", "Run fx doctor", false)) {
            s.page = .settings;
            s.settings_section = .about;
        }
    }
}

pub fn view(s: *State, c: *ui.Context) void {
    const col = ui.div(c).column().grow().wFull().itemsCenter().gap(28).px(40).pt(120).scrollY();
    defer col.end();

    art.view(c, 10);
    // No workspace yet: the first-run setup page.
    if (s.workspaces.items.len == 0) {
        firstRunPage(s, c);
        return;
    }
    // A failed agent replaces the home page with the recovery card, unless fx
    // itself is missing, in which case the install page comes first.
    if (s.agent_error) |err| {
        if (std.mem.indexOf(u8, err, "not found") != null or std.mem.indexOf(u8, err, "No such file") != null) {
            installPage(s, c);
        } else {
            agentDown(s, c, err);
        }
        return;
    }
    const name = if (s.workspaces.items.len > 0) s.workspaces.items[s.folder].name else "your project";
    ui.text(c, c.print("What should we build in {s}?", .{name}), .{ .size = 28, .line_height = 36, .weight = .medium });

    {
        const box = ui.div(c).column().wFull().maxW(680);
        defer box.end();
        composer.view(s, c);
    }

    if (s.workspaces.items.len == 0) return;
    const ws = &s.workspaces.items[s.folder];

    var live: usize = 0;
    var archived: usize = 0;
    for (ws.sessions.items) |session| {
        if (session.status == .running) live += 1;
        if (session.archived) archived += 1;
    }
    // A pending approval shows above the lists, even when no session is
    // listed yet: it is the way to answer without opening the session.
    if (s.preview_permission) |*pp| approvalCard(s, c, pp);

    // Nothing to list: the hero + composer is the whole page.
    if (ws.sessions.items.len == 0) return;

    const list = ui.div(c).column().wFull().maxW(680).gap(16);
    defer list.end();
    tabs(c, s, live, archived);

    const rows = ui.div(c).column().wFull().gap(0);
    defer rows.end();

    var shown: usize = 0;
    var first_heading = true;
    var prev_bucket: []const u8 = "";
    for (ws.sessions.items, 0..) |*session, i| {
        const in_tab = switch (s.home_tab) {
            .running => session.status == .running and !session.archived,
            .archived => session.archived,
            .recent => !session.archived,
        };
        if (!in_tab) continue;
        // Recent groups by day; the other tabs are flat.
        if (s.home_tab == .recent) {
            const bucket = bucketOf(session);
            if (first_heading or !std.mem.eql(u8, bucket, prev_bucket)) {
                dayHeading(c, bucket, first_heading);
                prev_bucket = bucket;
                first_heading = false;
            }
        }
        const note = noteFor(s, c, session);
        if (listRow(c, c.print("home-{d}", .{i}), session, note.text, note.color)) s.selectSession(i);
        shown += 1;
    }
    if (shown == 0) emptyList(c, s.home_tab);
}

/// "Today" / "Yesterday" / "Earlier", from the session's age.
fn bucketOf(session: *const Session) []const u8 {
    if (session.updated_at <= 0) return "Earlier";
    const secs = @import("nanoui").ui.clock.now() - session.updated_at;
    if (secs < 86_400) return "Today";
    if (secs < 172_800) return "Yesterday";
    return "Earlier";
}
