//! Changes panel (⌘\): file list and diff, mirroring fx-ui-main/src/views/changes.rs.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const t = @import("tokens.zig");
const w = @import("widgets.zig");
const git = @import("git.zig");
const State = @import("state.zig").State;

const width: f32 = 400;
const diff_limit: usize = 120;

fn codeColor(code: u8) ui.Color {
    return switch (code) {
        'A' => t.green_900,
        '?' => t.blue_700,
        'D' => t.red_700,
        else => t.amber_700,
    };
}

fn stat(c: *ui.Context, added: usize, removed: usize) void {
    // Wrapped in its own row so the two numbers stay one flex item and cannot
    // push a sibling onto a second line.
    const box = ui.div(c).row().gap(6).itemsCenter();
    defer box.end();
    if (added > 0 or removed == 0) {
        ui.text(c, c.print("+{d}", .{added}), .{ .size = 12, .mono = true, .family = t.mono_family, .color = t.green_900 });
    }
    if (removed > 0) {
        ui.text(c, c.print("−{d}", .{removed}), .{ .size = 12, .mono = true, .family = t.mono_family, .color = t.red_900 });
    }
}

fn fileRow(c: *ui.Context, change: git.Change, show_stat: bool) void {
    // Mirrors design changes.rs file_row(): status dot, file name (fixed),
    // then the directory as trailing muted detail; +/- stats at the right.
    const base = std.fs.path.basename(change.path);
    const dir = if (change.path.len > base.len) change.path[0 .. change.path.len - base.len - 1] else "";
    const fresh = change.code == '?' or change.code == 'A';
    const detail = if (dir.len == 0)
        (if (fresh) "new file" else "")
    else if (fresh)
        c.print("{s} · new file", .{dir})
    else
        dir;
    const row = ui.div(c).row().wFull().h(40).px(12).gap(10).itemsCenter();
    defer row.end();
    w.dot(c, codeColor(change.code));
    ui.text(c, base, .{ .size = 13, .line_height = 18, .color = t.gray_1000 });
    const spacer = ui.div(c).grow();
    defer spacer.end();
    if (show_stat) stat(c, change.added, change.removed);
    if (detail.len > 0) ui.text(c, detail, .{ .size = 12, .line_height = 16, .truncate = .ellipsis, .color = t.gray_700 });
}

/// The design's row_button(): a small pill, filled for the primary action.
fn rowButton(c: *ui.Context, label: []const u8, filled: bool) bool {
    var btn = ui.div(c).row().h(26).px(10).itemsCenter().rounded(6).control();
    if (filled) {
        btn = btn.bg(t.gray_1000);
    } else {
        btn = btn.border(t.alpha_400).borderW(1);
    }
    defer btn.end();
    ui.text(c, label, .{ .size = 12, .line_height = 16, .weight = .medium, .color = if (filled) t.background_100 else t.gray_900 });
    return btn.clicked();
}

/// A grouped card: heading (Staged / Not staged) with its Stage all /
/// Unstage all action, then a card of file rows separated by hairlines,
/// like the design's group().
fn group(c: *ui.Context, s: *State, title: []const u8, staged: bool) void {
    // Collect this group's changes first (bounded by the snapshot size).
    var indexes: [64]usize = undefined;
    var n: usize = 0;
    for (s.changes.changes.items, 0..) |ch, i| {
        if (ch.staged != staged) continue;
        if (n >= indexes.len) break;
        indexes[n] = i;
        n += 1;
    }
    if (n == 0) return;

    groupHeading(c, s, title, staged);
    const card = ui.div(c).column().wFull().rounded(12).bg(t.gray_100).border(t.alpha_300).borderW(1).clip();
    defer card.end();
    for (indexes[0..n], 0..) |idx, row_i| {
        if (row_i > 0) {
            const sep = ui.div(c).wFull().h(1).bg(t.alpha_200);
            sep.end();
        }
        const change = s.changes.changes.items[idx];
        ui.key(c, c.print("change-{d}-{d}", .{ @intFromBool(staged), idx }));
        const row = ui.div(c).row().wFull().h(40).px(12).gap(10).itemsCenter().control().hover(t.alpha_100);
        defer row.end();
        const hovered = row.hovered();
        // Hover swaps the +/- stats for the row actions (design's group_row).
        fileRow(c, change, !hovered);
        if (hovered) {
            if (!staged) {
                const disc = ui.div(c);
                defer disc.end();
                ui.text(c, "Discard", .{ .size = 12, .line_height = 16, .color = t.gray_900 });
                if (disc.clicked()) {
                    var d = @import("dialog.zig").Dialog{};
                    d.kind = .discard;
                    d.setTitle(c.print("Discard changes to {s}?", .{std.fs.path.basename(change.path)}));
                    d.setNote(if (change.code == '?')
                        "The new file is deleted. This can't be undone."
                    else
                        "The file goes back to its last commit. This can't be undone.");
                    d.setTarget(change.path);
                    s.dialog = d;
                }
            }
            const label: []const u8 = if (staged) "Unstage" else "Stage";
            if (rowButton(c, label, !staged)) s.stageToggle(change.path, staged);
        }
        if (row.clicked()) s.openChange(change.path);
    }
}

/// Heading row: title left, "Stage all"/"Unstage all" action right.
fn groupHeading(c: *ui.Context, s: *State, title: []const u8, staged: bool) void {
    const head = ui.div(c).row().wFull().px(2).pb(6).gap(10).itemsCenter();
    defer head.end();
    ui.text(c, title, .{ .size = 12, .line_height = 16, .color = t.gray_700 });
    const spacer = ui.div(c).grow();
    defer spacer.end();
    const action = ui.div(c);
    defer action.end();
    ui.text(c, if (staged) "Unstage all" else "Stage all", .{ .size = 12, .line_height = 16, .color = t.gray_900 });
    if (action.clicked()) s.stageAll(staged);
}

/// A Files / Diff segmented control in the changes header
/// (design's changes_tabs / segment).
fn changesTabs(s: *State, c: *ui.Context) void {
    const showing_diff = s.changes_open_file != null;
    const bar = ui.div(c).row().h(28).p(2).rounded(8).bg(t.gray_100).border(t.alpha_300).borderW(1);
    defer bar.end();
    for ([_]struct { id: []const u8, label: []const u8, diff: bool }{
        .{ .id = "tab-files", .label = "Files", .diff = false },
        .{ .id = "tab-diff", .label = "Diff", .diff = true },
    }) |tab| {
        ui.key(c, tab.id);
        const on = tab.diff == showing_diff;
        const seg = ui.div(c).row().hFull().px(10).itemsCenter().rounded(6).control()
            .bg(if (on) t.gray_300 else t.gray_100);
        defer seg.end();
        ui.text(c, tab.label, .{ .size = 12, .line_height = 16, .color = if (on) t.gray_1000 else t.gray_900 });
        if (seg.clicked()) {
            if (tab.diff) {
                // Switching to Diff opens the first file when none is open.
                if (s.changes_open_file == null and s.changes.changes.items.len > 0) {
                    s.openChange(s.changes.changes.items[0].path);
                }
            } else {
                s.closeChange();
            }
        }
    }
}

pub fn view(s: *State, c: *ui.Context) void {
    const snap = &s.changes;
    const panel = ui.div(c).column().w(width).hFull().bg(t.background_100).border(t.alpha_400).borderW(1);
    defer panel.end();

    {
        const totals = snap.totals();
        const head = ui.div(c).row().h(44).wFull().pl(16).pr(10).gap(10).itemsCenter();
        defer head.end();
        ui.text(c, "Changes", w.muted(13, 18));
        {
            const spacer = ui.div(c).grow();
            defer spacer.end();
        }
        // The right side is one row so its items cannot wrap onto a new line.
        const right = ui.div(c).row().gap(10).itemsCenter();
        defer right.end();
        if (snap.changes.items.len == 0) {
            ui.text(c, "Clean", w.faint(12, 16));
        } else {
            stat(c, totals.added, totals.removed);
        }
        changesTabs(s, c);
        if (w.iconButton(c, "close-changes", "x")) s.changes_open = false;
    }

    const body = ui.div(c).column().grow().wFull().scrollY().px(16).pt(8).pb(16);
    defer body.end();

    if (snap.err_msg) |err| {
        ui.text(c, err, .{ .size = 13, .color = t.red_900, .wrap = true });
        return;
    }
    if (snap.changes.items.len == 0) {
        const clean = ui.div(c).column().wFull().grow().center().gap(14).pb(80);
        defer clean.end();
        // A 40pt circular badge around the check (design's clean_view).
        {
            const badge = ui.div(c).size(40, 40).rounded(20).bg(t.gray_100)
                .border(t.alpha_300).borderW(1).center();
            defer badge.end();
            @import("icons.zig").draw(c, "check", 18, t.green_900);
        }
        ui.text(c, "Nothing to commit", .{ .size = 14, .weight = .medium, .color = t.gray_1000 });
        const branch = c.print("The working tree matches {s}.", .{snap.branch});
        ui.text(c, branch, w.faint(13, 18));
        if (snap.last_commit.len > 0) {
            ui.text(c, c.print("Last commit {s}", .{snap.last_commit}), w.faint(12, 16));
        }
        return;
    }

    if (s.changes_open_file) |path| {
        // Design's diff_view: the open file's card with a stage toggle and
        // diff, then the remaining files as folded cards with a chevron.
        for (snap.changes.items) |change| {
            if (!std.mem.eql(u8, change.path, path)) continue;
            const card = ui.div(c).column().wFull().rounded(12).bg(t.gray_100).border(t.alpha_300).borderW(1).clip();
            defer card.end();
            {
                const head = ui.div(c).row().wFull().h(40).px(12).gap(10).itemsCenter();
                defer head.end();
                fileRow(c, change, false);
                const stage_label: []const u8 = if (change.staged) "Unstage" else "Stage";
                if (rowButton(c, stage_label, !change.staged)) s.stageToggle(change.path, change.staged);
            }
            const hair = ui.div(c).wFull().h(1).bg(t.alpha_200);
            hair.end();
            @import("diff.zig").block(c, s.changes_diff.items, if (s.changes_full) s.changes_diff.items.len else diff_limit);
            if (!s.changes_full and s.changes_diff.items.len > diff_limit) {
                const hidden = s.changes_diff.items.len - diff_limit;
                if (@import("diff.zig").moreLines(c, "diff-more", hidden)) s.changes_full = true;
            }
        }
        // Remaining files as folded cards (design's folded list).
        for (snap.changes.items) |change| {
            if (std.mem.eql(u8, change.path, path)) continue;
            ui.key(c, c.print("folded-{d}", .{@intFromPtr(change.path.ptr)}));
            const card = ui.div(c).column().wFull().rounded(12).bg(t.gray_100).border(t.alpha_300).borderW(1).clip();
            defer card.end();
            const row = ui.div(c).row().wFull().h(40).px(12).gap(10).itemsCenter().control().hover(t.alpha_100);
            defer row.end();
            fileRow(c, change, true);
            @import("icons.zig").draw(c, "chevron-down", 12, t.gray_900);
            if (row.clicked()) s.openChange(change.path);
        }
    }

    // Design: two grouped cards with a 20pt gap, Staged above Not staged.
    const groups = ui.div(c).column().wFull().gap(20);
    defer groups.end();
    group(c, s, "Staged", true);
    group(c, s, "Not staged", false);
}
