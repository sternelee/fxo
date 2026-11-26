//! Command palette (⌘K): search commands and sessions, mirroring
//! fx-ui-main/src/views/palette.rs and nanoui's gallery palette overlay.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const t = @import("tokens.zig");
const w = @import("widgets.zig");
const State = @import("state.zig").State;

pub const Action = union(enum) {
    new_session,
    toggle_sidebar,
    open_folder,
    stop_turn,
    toggle_changes,
    open_settings,
    rename_session,
    remove_session,
    attach_images,
    open_session: usize,
};

pub const Entry = struct {
    group: []const u8,
    label: []const u8,
    detail: []const u8 = "",
    keys: []const u8 = "",
    /// Icon name from icons.zig; empty means a session row (drawn as a dot).
    icon: []const u8 = "",
    action: Action,
};

pub const Palette = struct {
    open: bool = false,
    query: ui.TextBuffer = .{},
    selected: usize = 0,

    pub fn deinit(p: *Palette) void {
        p.query.deinit();
    }

    pub fn toggle(p: *Palette, c: *ui.Context) void {
        if (p.open) {
            p.close(c);
            return;
        }
        p.open = true;
        p.query.clear();
        p.selected = 0;
        p.query.focus();
        c.changed = true;
    }

    pub fn close(p: *Palette, c: *ui.Context) void {
        p.open = false;
        c.focus = 0;
        c.changed = true;
    }

    /// Fills `out` with all commands and sessions; returns the count.
    pub fn collect(s: *State, out: []Entry) usize {
        var n: usize = 0;
        const put = struct {
            fn add(buf: []Entry, count: *usize, e: Entry) void {
                if (count.* < buf.len) {
                    buf[count.*] = e;
                    count.* += 1;
                }
            }
        }.add;

        put(out, &n, .{ .group = "Commands", .label = "New session", .keys = "⌘N", .icon = "plus", .action = .new_session });
        put(out, &n, .{ .group = "Commands", .label = "Toggle the sidebar", .keys = "⌘B", .icon = "panel-left", .action = .toggle_sidebar });
        put(out, &n, .{ .group = "Commands", .label = "Open folder", .keys = "⌘O", .icon = "folder", .action = .open_folder });
        put(out, &n, .{ .group = "Commands", .label = "Attach images", .icon = "image", .action = .attach_images });
        put(out, &n, .{ .group = "Commands", .label = "Toggle changes", .keys = "⌘\\", .icon = "lines", .action = .toggle_changes });
        put(out, &n, .{ .group = "Commands", .label = "Settings", .keys = "⌘,", .icon = "settings", .action = .open_settings });
        if (s.currentSession() != null) {
            put(out, &n, .{ .group = "This session", .label = "Rename this session", .icon = "pencil", .action = .rename_session });
            put(out, &n, .{ .group = "This session", .label = "Remove this session from the list", .icon = "trash", .action = .remove_session });
        }
        if (s.currentSession()) |session| {
            if (session.status == .running) {
                put(out, &n, .{ .group = "This session", .label = "Stop the running turn", .keys = "Esc", .icon = "x", .action = .stop_turn });
            }
        }
        if (s.workspaces.items.len > 0) {
            const ws = &s.workspaces.items[s.folder];
            for (ws.sessions.items, 0..) |session, i| {
                if (session.turns.items.len == 0) continue;
                put(out, &n, .{
                    .group = "Sessions",
                    .label = session.title,
                    .detail = ws.name,
                    .action = .{ .open_session = i },
                });
            }
        }
        return n;
    }

    fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
        if (needle.len == 0) return true;
        if (needle.len > haystack.len) return false;
        var i: usize = 0;
        while (i + needle.len <= haystack.len) : (i += 1) {
            var same = true;
            for (needle, 0..) |ch, j| {
                if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(ch)) {
                    same = false;
                    break;
                }
            }
            if (same) return true;
        }
        return false;
    }

    fn matches(q: []const u8, e: Entry) bool {
        if (q.len == 0) return true;
        return containsIgnoreCase(e.label, q) or containsIgnoreCase(e.detail, q);
    }

    fn filtered(s: *State, p: *const Palette, out: []Entry) usize {
        var all: [64]Entry = undefined;
        const total = collect(s, &all);
        const q = std.mem.trim(u8, p.query.text(), " \t\r\n");
        var n: usize = 0;
        for (all[0..total]) |e| {
            if (matches(q, e) and n < out.len) {
                out[n] = e;
                n += 1;
            }
        }
        return n;
    }

    fn takeKey(c: *ui.Context, sc: u21, comptime k: anytype, cmd: ui.Command) bool {
        if (c.shortcut(.{ .key = sc })) return true;
        if (c.input.key == k) {
            c.input.key = null;
            return true;
        }
        for (c.input.ops) |op| {
            if (op == .command and op.command == cmd) {
                c.input.ops = &.{};
                return true;
            }
        }
        return false;
    }

    /// Runs before other shortcuts so the palette owns the keys while open.
    pub fn handleKeys(s: *State, p: *Palette, c: *ui.Context) void {
        if (c.shortcut(.{ .key = 'k', .cmd = true })) {
            p.toggle(c);
            return;
        }
        if (!p.open) return;
        var list: [64]Entry = undefined;
        const count = filtered(s, p, &list);
        p.selected = if (count == 0) 0 else @min(p.selected, count - 1);

        if (takeKey(c, ui.Shortcut.escape, .escape, .cancel)) {
            p.close(c);
            return;
        }
        if (takeKey(c, ui.Shortcut.down, .down, .move_down)) {
            if (count > 0) p.selected = (p.selected + 1) % count;
            c.changed = true;
            return;
        }
        if (takeKey(c, ui.Shortcut.up, .up, .move_up)) {
            if (count > 0) p.selected = if (p.selected == 0) count - 1 else p.selected - 1;
            c.changed = true;
            return;
        }
        if (takeKey(c, ui.Shortcut.enter, .enter, .insert_newline)) {
            if (count > 0) p.run(s, c, list[p.selected].action);
        }
    }

    fn run(p: *Palette, s: *State, c: *ui.Context, action: Action) void {
        s.pending_action = action;
        p.close(c);
    }

    /// The overlay: scrim at layer 10, card at layer 11. Call last in the view.
    /// Renders a label with the query match in semibold, like the design's
    /// highlighted(). Falls back to a plain truncating label when nothing matches.
    fn highlighted(c: *ui.Context, label: []const u8, query: []const u8) void {
        _ = query;
        // A single text run: splitting the label into match/non-match runs
        // collapses to zero width inside this row's flex layout, so the label
        // stays whole and readable. Filtering already narrows the list.
        ui.text(c, label, .{ .size = 14, .line_height = 20, .truncate = .ellipsis, .color = t.gray_1000 });
    }

    pub fn overlay(s: *State, p: *Palette, c: *ui.Context) void {
        if (!p.open) return;

        {
            const scrim = ui.div(c).fixed().offset(0, 0).w(c.size.w).h(c.size.h).layer(10)
                .bg(.{ .r = 0, .g = 0, .b = 0, .a = 0.6 });
            const hit = scrim.interaction();
            scrim.end();
            if (hit.clicked) p.close(c);
        }

        const width = @min(600.0, @max(280.0, c.size.w - 48));
        const x = (c.size.w - width) / 2;
        const y = @max(24.0, @min(120.0, c.size.h * 0.133));
        const card = ui.div(c).fixed().offset(x, y).w(width).layer(11).column()
            .rounded(12).bg(t.background_100).border(t.alpha_400).borderW(1)
            .shadow(.{ .color = .{ .a = 0.6 }, .blur = 32, .y = 16 }).clip();
        defer card.end();

        var list: [64]Entry = undefined;
        const count = filtered(s, p, &list);
        p.selected = if (count == 0) 0 else @min(p.selected, count - 1);

        {
            const head = ui.div(c).row().wFull().h(52).px(16).gap(10).itemsCenter();
            defer head.end();
            @import("icons.zig").draw(c, "search", 16, t.gray_900);
            const field = ui.textField(c, &p.query, .{
                .placeholder = "Search commands and sessions",
                .bare = true,
                .width = .fill,
                .size = 16,
            });
            if (field.changed) p.selected = 0;
            if (field.submitted and count > 0) p.run(s, c, list[p.selected].action);
            // The Esc key hint is a small bordered pill (design's palette-esc).
            ui.key(c, "palette-esc");
            const esc = ui.div(c).row().h(20).px(6).rounded(4).control()
                .bg(t.gray_100).border(t.alpha_400).borderW(1);
            defer esc.end();
            ui.text(c, "Esc", .{ .size = 12, .line_height = 16, .color = t.gray_900 });
            if (esc.clicked()) p.close(c);
        }
        {
            // A hairline under the header, like the design's border_b_1.
            const rule = ui.div(c).wFull().h(1).bg(t.alpha_400);
            rule.end();
        }

        {
            const rows = ui.div(c).column().wFull().maxH(360).scrollY().p(8).gap(1);
            defer rows.end();
            var last_group: []const u8 = "";
            for (list[0..count], 0..) |e, i| {
                if (!std.mem.eql(u8, e.group, last_group)) {
                    {
                        const heading = ui.div(c).row().wFull().px(8).pt(if (i == 0) 4 else 8).pb(4);
                        defer heading.end();
                        ui.text(c, e.group, .{ .size = 12, .line_height = 16, .weight = .medium, .color = t.gray_900 });
                    }
                    last_group = e.group;
                }
                ui.key(c, c.print("pal-{d}", .{i}));
                const on = i == p.selected;
                const row = ui.div(c).row().wFull().h(40).px(8).gap(10).itemsCenter().rounded(6)
                    .control().bg(if (on) t.alpha_200 else t.background_100).hover(t.alpha_100);
                defer row.end();
                if (row.clicked()) p.run(s, c, e.action);
                // Session rows get a dot; commands get their own icon
                // (design's palette_row mark). Both are drawn directly in the
                // row so the label after them keeps its natural width.
                if (e.icon.len > 0) {
                    @import("icons.zig").draw(c, e.icon, 16, if (on) t.gray_1000 else t.gray_900);
                } else {
                    w.dot(c, t.gray_500);
                }
                highlighted(c, e.label, p.query.text());
                {
                    const spacer = ui.div(c).grow();
                    defer spacer.end();
                }
                const trailing = if (e.keys.len > 0) e.keys else e.detail;
                if (trailing.len > 0) ui.text(c, trailing, .{ .size = 12, .color = t.gray_900 });
            }
            if (count == 0) {
                const empty = ui.div(c).wFull().p(22).center();
                defer empty.end();
                ui.text(c, "Nothing matches", .{ .size = 13, .color = t.gray_700 });
            }
        }

        {
            // The footer is separated by a hairline (design's palette_footer).
            const rule2 = ui.div(c).wFull().h(1).bg(t.alpha_400);
            rule2.end();
            const foot = ui.div(c).row().wFull().h(40).px(16).gap(16).itemsCenter()
                .bg(t.background_200);
            defer foot.end();
            ui.text(c, "↑↓ Navigate", .{ .size = 12, .color = t.gray_900 });
            ui.text(c, "⏎ Run", .{ .size = 12, .color = t.gray_900 });
            {
                const spacer = ui.div(c).grow();
                defer spacer.end();
            }
            ui.text(c, "⌘K", .{ .size = 12, .color = t.gray_700 });
        }
    }
};

test "collect returns commands and sessions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s: State = .{ .alloc = alloc };
    s.addWorkspace("/example/project");
    s.newSession();
    const turn = @import("state.zig").Turn.init(alloc, "hi");
    s.currentSession().?.turns.append(alloc, turn) catch unreachable;
    var entries: [64]Entry = undefined;
    const n = Palette.collect(&s, &entries);
    try std.testing.expect(n >= 4);
    try std.testing.expectEqualStrings("New session", entries[0].label);
}
