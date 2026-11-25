//! The six settings pages, backed by the fx CLI snapshot in `State.fx_info`.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const t = @import("tokens.zig");
const w = @import("widgets.zig");
const icons = @import("icons.zig");
const shell = @import("settings.zig");
const State = @import("state.zig").State;
const fxcli = @import("fxcli.zig");

fn gap(c: *ui.Context, amount: f32) void {
    ui.div(c).h(amount).end();
}

fn statusDot(c: *ui.Context, on: bool) void {
    w.dot(c, if (on) t.green_900 else t.gray_500);
}

pub fn models(s: *State, c: *ui.Context) void {
    const info = &s.fx_info;
    shell.pageTitle(c, "Models & accounts", if (info.connected())
        "fx answers with whichever account the chosen model belongs to."
    else
        "Connect one account and fx can start answering.");

    shell.groupTitle(c, "Accounts");
    {
        const card = shell.cardStart(c);
        defer card.end();
        if (!info.loaded) {
            shell.row(c, "Loading…", "Reading fx status");
        } else if (info.provider_count == 0) {
            // Nothing can answer yet: say so plainly (design's nothing_connected).
            const row = ui.div(c).row().wFull().h(44).px(16).gap(10).itemsCenter();
            defer row.end();
            w.dot(c, t.amber_700);
            ui.text(c, "Nothing can answer a prompt yet", .{ .size = 13, .line_height = 18, .color = t.gray_1000 });
            {
                const spacer = ui.div(c).grow();
                defer spacer.end();
            }
            ui.text(c, "Connect any one below", .{ .size = 13, .line_height = 18, .color = t.gray_900 });
        } else {
            for (info.providers[0..info.provider_count], 0..) |provider, i| {
                if (i > 0) shell.separator(c);
                const is_default = std.mem.eql(u8, provider.slice(), info.provider.slice()) or
                    std.mem.indexOf(u8, info.model.slice(), provider.slice()) != null;
                accountRow(s, c, provider.slice(), is_default, i);
            }
        }
    }
    shell.groupTitle(c, "New sessions");
    {
        const card = shell.cardStart(c);
        defer card.end();
        const model = if (info.loaded and info.model.slice().len > 0) fxcli.modelName(c.alloc(), info.model.slice()) else "fx default";
        // Both rows open the same popup the composer uses, anchored on the row.
        if (shell.selectRow(c, "settings-model", "Model", "What new sessions answer with.", model)) |at| {
            s.composer_menu = .model;
            s.menu_anchor = at;
        }
        shell.separator(c);
        const mode = if (info.permission_mode.slice().len > 0) info.permission_mode.slice() else "ask";
        if (shell.selectRow(c, "settings-mode", "Permissions", "What fx may do without asking.", mode)) |at| {
            s.composer_menu = .mode;
            s.menu_anchor = at;
        }
    }
}

/// An account row: a 28pt badge (inverted when in use), the provider name and
/// its state, then the action (design's sign_in_row).
fn accountRow(s: *State, c: *ui.Context, provider: []const u8, is_default: bool, index: usize) void {
    const row = ui.div(c).row().wFull().h(60).px(16).gap(12).itemsCenter();
    defer row.end();
    {
        // The badge: the provider's initial, inverted while it is in use.
        const badge = ui.div(c).size(28, 28).rounded(7).center()
            .bg(if (is_default) t.gray_1000 else t.gray_300);
        defer badge.end();
        const initial: []const u8 = if (provider.len > 0)
            c.print("{c}", .{std.ascii.toUpper(provider[0])})
        else
            "?";
        ui.text(c, initial, .{ .size = 12, .weight = .bold, .color = if (is_default) t.background_100 else t.gray_1000 });
    }
    {
        const col = ui.div(c).column().grow().gap(2);
        defer col.end();
        ui.text(c, provider, .{ .size = 14, .line_height = 20, .truncate = .ellipsis, .color = t.gray_1000 });
        const auth = if (s.fx_info.auth.slice().len > 0) s.fx_info.auth.slice() else "configured";
        const detail = if (is_default)
            c.print("{s} · new sessions start here", .{auth})
        else
            "Connected";
        ui.text(c, detail, .{ .size = 13, .line_height = 18, .truncate = .ellipsis, .color = t.gray_900 });
    }
    {
        const actions = ui.div(c).row().gap(4).itemsCenter();
        defer actions.end();
        if (!is_default) {
            if (w.button(c, c.print("use-{d}", .{index}), "Make default", false)) {
                s.fx_info.provider.set(provider);
                State.setConfigDefault("provider", provider);
                s.status_line = c.print("Default account: {s}", .{provider});
            }
        }
        if (w.button(c, c.print("signout-{d}", .{index}), "Sign out", false)) {
            s.status_line = c.print("Run `fx logout {s}` in a terminal", .{provider});
        }
    }
}

pub fn behaviour(s: *State, c: *ui.Context) void {
    shell.pageTitle(c, "Behaviour", "How new sessions think, and what they may do without asking.");
    State.loadInstructions(s);
    shell.groupTitle(c, "New sessions");
    {
        const card = shell.cardStart(c);
        defer card.end();
        // Thinking: segmented levels, written to fx's global effort default.
        const think = ui.div(c).column().wFull().gap(14).p(16);
        defer think.end();
        ui.text(c, "Thinking", .{ .size = 14, .line_height = 20, .color = t.gray_1000 });
        ui.text(c, "More thinking is slower and costs more, and catches more.", w.faint(13, 18));
        {
            const seg = ui.div(c).row().wFull().h(32).p(2).gap(2).rounded(9).bg(t.background_100).border(t.alpha_300).borderW(1);
            defer seg.end();
            const levels = [_]struct { label: []const u8, value: []const u8 }{
                .{ .label = "Auto", .value = "auto" },
                .{ .label = "Off", .value = "none" },
                .{ .label = "Low", .value = "low" },
                .{ .label = "Medium", .value = "medium" },
                .{ .label = "High", .value = "high" },
                .{ .label = "Max", .value = "xhigh" },
            };
            const current = s.fx_info.effort.slice();
            for (levels, 0..) |lv, i| {
                ui.key(c, c.print("effort-{d}", .{i}));
                const on = current.len > 0 and std.mem.eql(u8, current, lv.value);
                const b = ui.div(c).row().grow().hFull().center().rounded(7)
                    .bg(if (on) t.gray_300 else t.background_100).control();
                defer b.end();
                ui.text(c, lv.label, .{ .size = 13, .color = if (on) t.gray_1000 else t.gray_900 });
                if (b.clicked()) {
                    State.setConfigDefault("effort", lv.value);
                    s.fx_info.effort.set(lv.value);
                }
            }
        }
        shell.separator(c);
        // Fast mode toggle, written to fx's global fast_mode default.
        const fast = ui.div(c).row().wFull().gap(12).itemsCenter().px(16).py(14);
        defer fast.end();
        const fcol = ui.div(c).column().grow().gap(2);
        defer fcol.end();
        ui.text(c, "Fast mode", .{ .size = 14, .line_height = 20, .color = t.gray_1000 });
        ui.text(c, "Quicker answers on models that offer it", w.faint(13, 18));
        if (shell.toggle(c, "settings-fast", s.fast_mode)) {
            s.fast_mode = !s.fast_mode;
            State.setConfigDefault("fast_mode", if (s.fast_mode) "true" else "false");
        }
        shell.separator(c);
        // Notifications: one row with its switch (design's notify_row).
        {
            const row = ui.div(c).row().wFull().px(16).py(14).gap(12).itemsCenter();
            defer row.end();
            {
                const col = ui.div(c).column().grow().gap(2);
                defer col.end();
                ui.text(c, "Notify me", .{ .size = 14, .line_height = 20, .color = t.gray_1000 });
                ui.text(c, "When a turn needs you or finishes in the background", w.faint(13, 18));
            }
            if (shell.toggle(c, "settings-notify", !s.notify_muted)) s.notify_muted = !s.notify_muted;
        }
    }
    // Instructions: the workspace's AGENTS.md, which fx reads into every
    // session (design's instructions_field).
    shell.groupTitle(c, "Instructions");
    {
        const card = ui.div(c).column().wFull().gap(10).rounded(12).bg(t.gray_100)
            .border(t.alpha_300).borderW(1).p(6);
        defer card.end();
        const area = ui.textArea(c, &s.instructions, .{
            .width = .fill,
            .size = 13,
            .min_lines = 6,
            .max_lines = 14,
            .bare = true,
            .placeholder = "Notes fx should follow in this workspace",
            .color = t.gray_1000,
        });
        if (area.changed) State.saveInstructions(s);
    }
    ui.text(c, "Added to every new session, after fx's own instructions.", w.faint(12, 16));
    // Extra folders: the directories fx reaches as well as the workspace
    // (design's extra_folders).
    shell.groupTitle(c, "Extra folders");
    {
        const card = shell.cardStart(c);
        defer card.end();
        for (s.fx_info.extra_dirs[0..s.fx_info.extra_count], 0..) |dir, i| {
            if (i > 0) shell.separator(c);
            const row = ui.div(c).row().wFull().h(48).px(16).gap(12).itemsCenter();
            defer row.end();
            icons.draw(c, "folder", 16, t.gray_900);
            {
                const col = ui.div(c).column().grow().gap(2);
                defer col.end();
                ui.text(c, dir.slice(), .{ .size = 13, .line_height = 18, .mono = true, .family = t.mono_family, .truncate = .ellipsis, .color = t.gray_1000 });
            }
        }
        if (s.fx_info.extra_count > 0) shell.separator(c);
        {
            const row = ui.div(c).row().wFull().px(16).py(14).gap(12).itemsCenter();
            defer row.end();
            {
                const col = ui.div(c).column().grow().gap(2);
                defer col.end();
                const lead = if (s.fx_info.extra_count == 0) "Only this folder" else "Add another";
                ui.text(c, lead, .{ .size = 14, .line_height = 20, .color = t.gray_1000 });
                const where = if (s.fx_info.workspace.slice().len > 0) s.fx_info.workspace.slice() else "the workspace";
                ui.text(c, c.print("fx reaches these as well as {s}", .{where}), w.faint(13, 18));
            }
            // The limit fx enforces, so the button says why it is off.
            const full = s.fx_info.extra_limit > 0 and s.fx_info.extra_count >= s.fx_info.extra_limit;
            const b = ui.div(c).row().h(30).px(12).rounded(8).border(t.alpha_300).borderW(1).itemsCenter().gap(6)
                .bg(if (full) t.gray_200 else t.background_100).control();
            defer b.end();
            ui.text(c, "Add folder…", .{ .size = 13, .color = if (full) t.gray_600 else t.gray_1000 });
            if (b.clicked() and !full) State.addExtraFolder(s);
        }
    }
    shell.groupTitle(c, "Always allowed");
    {
        const card = shell.cardStart(c);
        defer card.end();
        if (s.fx_info.rule_count == 0) {
            shell.row(c, "Nothing is always allowed yet", "Choose Always allow on an approval to add a rule here");
        } else {
            for (s.fx_info.rules[0..s.fx_info.rule_count], 0..) |rule, i| {
                if (i > 0) shell.separator(c);
                ruleRow(c, rule.slice());
            }
        }
    }
    // The footnote explains where these rules come from.
    ui.text(c, "Added when you choose Always allow on an approval.", w.faint(12, 16));
}

/// A rule row: a `$` badge, then the rule in mono (design's rule_row).
fn ruleRow(c: *ui.Context, rule: []const u8) void {
    const row = ui.div(c).row().wFull().h(48).px(16).gap(12).itemsCenter();
    defer row.end();
    {
        const badge = ui.div(c).size(24, 24).rounded(6).bg(t.gray_200).center();
        defer badge.end();
        ui.text(c, "$", .{ .size = 12, .mono = true, .family = t.mono_family, .color = t.gray_900 });
    }
    ui.text(c, rule, .{ .size = 13, .line_height = 18, .mono = true, .family = t.mono_family, .truncate = .ellipsis, .color = t.gray_1000 });
}

/// A server's status dot colour and label (design's state_mark).
fn mcpState(srv: *const fxcli.Server, c: *ui.Context) struct { color: ui.Color, label: []const u8 } {
    const st = srv.status.slice();
    if (std.mem.eql(u8, st, "ready") or std.mem.eql(u8, st, "ok") or std.mem.eql(u8, st, "connected")) {
        return .{ .color = t.green_900, .label = if (srv.tools > 0) c.print("{d} tool{s}", .{ srv.tools, if (srv.tools == 1) "" else "s" }) else "Ready" };
    }
    if (std.mem.eql(u8, st, "failed") or std.mem.eql(u8, st, "error")) return .{ .color = t.red_700, .label = "Failed" };
    if (std.mem.eql(u8, st, "waiting") or std.mem.eql(u8, st, "signed-out")) return .{ .color = t.amber_700, .label = "Waiting" };
    if (std.mem.eql(u8, st, "rejected")) return .{ .color = t.gray_600, .label = "Rejected" };
    // fx reports a server it has not contacted yet as not_started.
    if (std.mem.eql(u8, st, "not_started")) return .{ .color = t.gray_600, .label = "Not started" };
    if (st.len > 0) return .{ .color = t.gray_600, .label = st };
    return .{ .color = t.gray_600, .label = "Not checked" };
}

/// A 28pt tile: a remote server's initial, or `›_` for a local one.
fn mcpTile(c: *ui.Context, srv: *const fxcli.Server) void {
    const box = ui.div(c).size(28, 28).rounded(7).bg(t.gray_300).center();
    defer box.end();
    const remote = std.mem.eql(u8, srv.source.slice(), "remote");
    const mark: []const u8 = if (remote and srv.name.slice().len > 0)
        c.print("{c}", .{std.ascii.toUpper(srv.name.slice()[0])})
    else
        "›_";
    ui.text(c, mark, .{ .size = 12, .mono = true, .family = t.mono_family, .weight = .bold, .color = t.gray_1000 });
}

pub fn mcp(s: *State, c: *ui.Context) void {
    const info = &s.fx_info;
    // Title on the left, Add server on the right (design's page_head).
    {
        const head = ui.div(c).row().wFull().itemsEnd().gap(16);
        defer head.end();
        {
            const col = ui.div(c).column().grow().gap(4);
            defer col.end();
            shell.pageTitle(c, "MCP servers", "Tools fx can reach beyond your files. fx keeps their logins.");
        }
        if (w.button(c, "mcp-add", "Add server", true)) {
            s.mcp_adding = true;
            s.mcp_add_error = null;
        }
    }
    {
        const card = shell.cardStart(c);
        defer card.end();
        // The inline add form sits above the rows while it is open
        // (design's add_form).
        if (s.mcp_adding) {
            const form = ui.div(c).row().wFull().h(60).px(16).py(10).gap(8).itemsCenter();
            defer form.end();
            {
                const name_box = ui.div(c).column().w(160).gap(0);
                defer name_box.end();
                _ = ui.textField(c, &s.mcp_name, .{
                    .placeholder = "Name",
                    .width = .fill,
                    .size = 13,
                    .bare = false,
                    .color = t.gray_1000,
                });
            }
            {
                const addr_box = ui.div(c).column().grow().gap(0);
                defer addr_box.end();
                _ = ui.textField(c, &s.mcp_address, .{
                    .placeholder = "URL, or the command that starts it",
                    .width = .fill,
                    .size = 13,
                    .bare = false,
                    .color = t.gray_1000,
                });
            }
            if (w.button(c, "mcp-add-cancel", "Cancel", false)) {
                s.mcp_adding = false;
                s.mcp_add_error = null;
            }
            if (w.button(c, "mcp-add-go", "Add", true)) State.addMcpServer(s);
            shell.separator(c);
        }
        if (s.mcp_add_error) |why| {
            const err = ui.div(c).row().wFull().px(16).py(8).gap(8).itemsCenter();
            defer err.end();
            w.dot(c, t.red_700);
            ui.text(c, why, .{ .size = 12, .line_height = 16, .color = t.red_700 });
            shell.separator(c);
        }
        if (info.server_count == 0) {
            shell.row(c, "No servers yet", "Add one by its URL, or the command that starts it.");
        } else {
            for (info.servers[0..info.server_count], 0..) |*srv, i| {
                if (i > 0) shell.separator(c);
                const mark = mcpState(srv, c);
                const row = ui.div(c).row().wFull().px(16).py(14).gap(12).itemsCenter();
                defer row.end();
                mcpTile(c, srv);
                {
                    const col = ui.div(c).column().grow().gap(2);
                    defer col.end();
                    ui.text(c, srv.name.slice(), .{ .size = 14, .line_height = 20, .color = t.gray_1000 });
                    // The detail line says what is wrong when it failed, what
                    // it is waiting for, and otherwise the address in mono
                    // (design's mcp_row detail).
                    const failed = srv.error_msg.slice();
                    const waiting = std.mem.eql(u8, srv.status.slice(), "waiting") or
                        std.mem.eql(u8, srv.status.slice(), "signed-out");
                    if (failed.len > 0) {
                        ui.text(c, failed, .{ .size = 12, .line_height = 18, .truncate = .ellipsis, .color = t.gray_900 });
                    } else if (waiting) {
                        ui.text(c, "Waiting for you to approve it", .{ .size = 12, .line_height = 18, .color = t.gray_900 });
                    } else {
                        const addr = if (srv.address.slice().len > 0)
                            srv.address.slice()
                        else if (srv.transport.slice().len > 0)
                            srv.transport.slice()
                        else
                            srv.source.slice();
                        if (addr.len > 0) ui.text(c, addr, .{ .size = 12, .line_height = 18, .mono = true, .family = t.mono_family, .truncate = .ellipsis, .color = t.gray_900 });
                    }
                }
                // Status mark: a coloured dot plus its label.
                {
                    const status = ui.div(c).row().gap(6).itemsCenter();
                    defer status.end();
                    w.dot(c, mark.color);
                    ui.text(c, mark.label, .{ .size = 12, .line_height = 16, .color = t.gray_900 });
                }
            }
        }
    }
}

pub fn skills(s: *State, c: *ui.Context) void {
    const info = &s.fx_info;
    shell.pageTitle(c, "Skills", "Instructions fx loads when a request needs them.");

    // A filter field, like the design's skills_filter_field.
    {
        const box = ui.div(c).row().wFull().h(36).px(12).gap(10).itemsCenter().rounded(10)
            .bg(t.gray_100).border(t.alpha_300).borderW(1);
        defer box.end();
        @import("icons.zig").draw(c, "search", 14, t.gray_700);
        _ = ui.textField(c, &s.skill_filter, .{ .placeholder = "Filter skills", .bare = true, .width = .fill, .size = 13 });
    }

    const query = std.mem.trim(u8, s.skill_filter.text(), " \t");
    var shown: usize = 0;
    for (info.skills.items[0..info.skill_count]) |skill| {
        if (query.len > 0 and std.mem.indexOf(u8, skill.name.slice(), query) == null and
            std.mem.indexOf(u8, skill.description.slice(), query) == null) continue;
        shown += 1;
    }

    // The counted header: title, the folder it came from, and the count.
    {
        const head = ui.div(c).row().wFull().px(2).gap(8).itemsCenter();
        defer head.end();
        ui.text(c, "Available", .{ .size = 13, .line_height = 18, .weight = .medium, .color = t.gray_1000 });
        const folder = if (info.skill_count > 0 and info.skills.items[0].source.slice().len > 0)
            c.print("~/{s}/skills", .{info.skills.items[0].source.slice()})
        else
            "~/.fx/skills";
        ui.text(c, folder, .{ .size = 12, .line_height = 16, .mono = true, .family = t.mono_family, .color = t.gray_700 });
        {
            const spacer = ui.div(c).grow();
            defer spacer.end();
        }
        ui.text(c, c.print("{d}", .{shown}), .{ .size = 12, .line_height = 16, .color = t.gray_700 });
    }

    {
        const card = shell.cardStart(c);
        defer card.end();
        if (info.skill_count == 0) {
            shell.row(c, "No skills found", "Add a SKILL.md under .fx/skills or ~/.fx/skills");
        } else if (shown == 0) {
            shell.row(c, "Nothing matches", c.print("No skill matches \"{s}\"", .{query}));
        } else {
            var first = true;
            for (info.skills.items[0..info.skill_count], 0..) |skill, i| {
                if (query.len > 0 and std.mem.indexOf(u8, skill.name.slice(), query) == null and
                    std.mem.indexOf(u8, skill.description.slice(), query) == null) continue;
                if (!first) shell.separator(c);
                first = false;
                skillRow(c, skill, i);
            }
        }
    }
}

/// A skill row: `/name` in mono, its description, and an Open button that
/// reveals the skill's folder (design's skill_row).
fn skillRow(c: *ui.Context, skill: fxcli.SkillItem, index: usize) void {
    const row = ui.div(c).row().wFull().h(56).px(16).gap(12).itemsCenter();
    defer row.end();
    {
        const col = ui.div(c).column().grow().gap(2);
        defer col.end();
        ui.text(c, c.print("/{s}", .{skill.name.slice()}), .{ .size = 13, .line_height = 20, .mono = true, .family = t.mono_family, .color = t.gray_1000 });
        const detail = if (skill.description.slice().len > 0) skill.description.slice() else "SKILL.md";
        ui.text(c, detail, .{ .size = 13, .line_height = 18, .truncate = .ellipsis, .color = t.gray_900 });
    }
    if (w.button(c, c.print("skill-open-{d}", .{index}), "Open", false)) reveal(skill.path.slice());
}

fn compact(n: f64, buf: []u8) []const u8 {
    if (n >= 1e9) return std.fmt.bufPrint(buf, "{d:.1}B", .{n / 1e9}) catch "";
    if (n >= 1e6) return std.fmt.bufPrint(buf, "{d:.1}M", .{n / 1e6}) catch "";
    if (n >= 1e3) return std.fmt.bufPrint(buf, "{d:.1}K", .{n / 1e3}) catch "";
    return std.fmt.bufPrint(buf, "{d:.0}", .{n}) catch "";
}

pub fn usage(s: *State, c: *ui.Context) void {
    const info = &s.fx_info;
    const source = if (info.usage_source.slice().len > 0) info.usage_source.slice() else "Your provider";
    // Title on the left, the period segments on the right (design's usage_header).
    {
        const head = ui.div(c).row().wFull().itemsEnd().gap(16);
        defer head.end();
        {
            const col = ui.div(c).column().grow().gap(4);
            defer col.end();
            shell.pageTitle(c, "Usage", c.print("{s}. Days are in UTC.", .{source}));
        }
        const seg = ui.div(c).row().h(30).p(2).gap(2).rounded(8).bg(t.gray_100).border(t.alpha_300).borderW(1);
        defer seg.end();
        for ([_]struct { id: []const u8, label: []const u8, value: []const u8 }{
            .{ .id = "p-today", .label = "Today", .value = "today" },
            .{ .id = "p-7d", .label = "7 days", .value = "7d" },
            .{ .id = "p-month", .label = "Month", .value = "month" },
        }) |p| {
            ui.key(c, p.id);
            const on = std.mem.eql(u8, s.usage_period, p.value);
            const b = ui.div(c).row().hFull().px(10).itemsCenter().rounded(6).control()
                .bg(if (on) t.gray_300 else t.gray_100);
            defer b.end();
            ui.text(c, p.label, .{ .size = 12, .line_height = 16, .color = if (on) t.gray_1000 else t.gray_900 });
            if (b.clicked() and !on) {
                s.usage_period = p.value;
                // The loader thread re-reads usage for the chosen period, so
                // the click never blocks a frame on fx subprocesses.
                if (s.fx_loader) |loader| {
                    loader.setPeriod(p.value);
                } else {
                    @import("fxcli.zig").gatherPeriod(s.alloc, &s.fx_info, p.value);
                }
            }
        }
    }

    if (!info.loaded) {
        shell.row(c, "Loading…", "Reading fx usage");
        return;
    }
    if (std.mem.eql(u8, info.usage_status.slice(), "failed") or std.mem.eql(u8, info.usage_status.slice(), "unavailable")) {
        // The provider cannot report usage: say why, then still show the
        // zeroed tiles so the page keeps its shape (design's usage_failure).
        const detail = if (info.usage_reason.slice().len > 0) info.usage_reason.slice() else "not available";
        {
            const card = shell.cardStart(c);
            defer card.end();
            shell.row(c, "Usage unavailable", detail);
        }
        gap(c, 16);
        const tiles = ui.div(c).row().wFull().gap(1).rounded(12).bg(t.gray_100).border(t.alpha_300).borderW(1);
        defer tiles.end();
        tile(c, "Spend", "$0.00");
        tile(c, "Requests", "0");
        tile(c, "Tokens", "0");
        return;
    }

    {
        const tiles = ui.div(c).row().wFull().gap(1).rounded(12).bg(t.gray_100).border(t.alpha_300).borderW(1);
        defer tiles.end();
        var buf1: [32]u8 = undefined;
        var buf2: [32]u8 = undefined;
        var buf3: [32]u8 = undefined;
        tile(c, "Spend", std.fmt.bufPrint(&buf1, "${d:.2}", .{info.spend}) catch "$0");
        tile(c, "Requests", std.fmt.bufPrint(&buf2, "{d:.0}", .{info.request_count}) catch "0");
        tile(c, "Tokens", compact(info.total_tokens, &buf3));
    }
    gap(c, 16);
    // Token breakdown: a stacked bar plus its five labelled parts
    // (design's token_parts).
    {
        const parts = [_]struct { label: []const u8, value: f64, color: ui.Color }{
            .{ .label = "Input", .value = info.input_tokens, .color = t.gray_1000 },
            .{ .label = "Output", .value = info.output_tokens, .color = t.blue_700 },
            .{ .label = "Cache read", .value = info.cache_read_tokens, .color = t.gray_600 },
            .{ .label = "Cache write", .value = info.cache_write_tokens, .color = t.gray_500 },
            .{ .label = "Reasoning", .value = info.reasoning_tokens, .color = t.amber_700 },
        };
        var sum: f64 = 0;
        for (parts) |p| sum += p.value;
        if (sum > 0) {
            shell.groupTitle(c, "Where the tokens went");
            const card = shell.cardStart(c);
            defer card.end();
            {
                const bar = ui.div(c).row().wFull().h(8).rounded(4).clip();
                defer bar.end();
                for (parts) |p| {
                    if (p.value <= 0) continue;
                    // Each segment takes its share of the bar's width.
                    const w_frac: f32 = @floatCast(p.value / sum);
                    const seg = ui.div(c).h(8).w(600 * w_frac).bg(p.color);
                    seg.end();
                }
            }
            for (parts) |p| {
                if (p.value <= 0) continue;
                const row = ui.div(c).row().wFull().px(16).py(8).gap(10).itemsCenter();
                defer row.end();
                w.dot(c, p.color);
                ui.text(c, p.label, .{ .size = 13, .line_height = 18, .color = t.gray_900 });
                {
                    const spacer = ui.div(c).grow();
                    defer spacer.end();
                }
                var buf: [32]u8 = undefined;
                ui.text(c, compact(p.value, &buf), .{ .size = 12, .mono = true, .family = t.mono_family, .color = t.gray_900 });
            }
        }
    }
    gap(c, 16);
    shell.groupTitle(c, "By model");
    {
        const card = shell.cardStart(c);
        defer card.end();
        if (info.model_rows == 0) {
            shell.row(c, "No requests", "Nothing was sent in this period");
        } else {
            for (info.models[0..info.model_rows], 0..) |m, i| {
                if (i > 0) shell.separator(c);
                const label = fxcli.modelName(c.alloc(), m.name.slice());
                shell.row(c, label, c.print("{d:.0} requests · ${d:.2}", .{ m.requests, m.spend }));
            }
        }
    }
    gap(c, 8);
    ui.text(c, source, w.faint(12, 16));
}

fn tile(c: *ui.Context, label: []const u8, value: []const u8) void {
    const box = ui.div(c).column().grow().gap(6).p(16);
    defer box.end();
    ui.text(c, label, w.faint(13, 18));
    ui.text(c, value, .{ .size = 24, .line_height = 30, .weight = .medium, .color = t.gray_1000 });
}

pub fn about(s: *State, c: *ui.Context) void {
    const info = &s.fx_info;
    shell.pageTitle(c, "About", "fx desktop, built with Zig and nanoui.");
    {
        const hero = ui.div(c).row().wFull().gap(20).p(20).rounded(12).bg(t.gray_100).border(t.alpha_300).borderW(1);
        defer hero.end();
        ui.text(c, "fx", .{ .size = 28, .weight = .medium, .color = t.gray_1000 });
        const col = ui.div(c).column().grow().gap(2);
        defer col.end();
        const version = if (info.doctor_version.slice().len > 0) info.doctor_version.slice() else "unknown";
        ui.text(c, c.print("fx {s}", .{version}), .{ .size = 20, .line_height = 26, .weight = .medium, .color = t.gray_1000 });
        ui.text(c, "Native UI on nanoui, with fx embedded in-process", w.faint(13, 18));
    }
    gap(c, 8);
    // Health: a "Run again" action plus each check fx doctor reported
    // (design's health_section / check_row).
    {
        const head = ui.div(c).row().wFull().px(2).gap(8).itemsCenter();
        defer head.end();
        ui.text(c, "Health", .{ .size = 13, .line_height = 18, .weight = .medium, .color = t.gray_1000 });
        {
            const spacer = ui.div(c).grow();
            defer spacer.end();
        }
        if (w.button(c, "doctor-again", "Run again", false)) {
            @import("fxcli.zig").gather(s.alloc, &s.fx_info);
            s.status_line = "Ran fx doctor";
        }
    }
    {
        const card = shell.cardStart(c);
        defer card.end();
        if (!info.loaded) {
            shell.row(c, "Checking…", "Running fx doctor");
        } else if (info.check_count == 0) {
            shell.row(c, "No checks", "fx doctor printed nothing");
        } else {
            for (info.checks[0..info.check_count], 0..) |check, i| {
                if (i > 0) shell.separator(c);
                checkRow(c, check);
            }
        }
    }
    gap(c, 8);
    shell.groupTitle(c, "This app");
    {
        const card = shell.cardStart(c);
        defer card.end();
        shell.row(c, "Version", "0.0.0 · development build");
        shell.separator(c);
        shell.row(c, "Updates", if (info.channel.slice().len > 0) info.channel.slice() else "Not checked yet");
    }
    gap(c, 8);
    // The two directories fx and this app keep their state in
    // (design's Files group).
    shell.groupTitle(c, "Files");
    {
        const card = shell.cardStart(c);
        defer card.end();
        fileRow(c, "reveal-fx", "fx settings", info.fx_home.slice());
        shell.separator(c);
        fileRow(c, "reveal-app", "Workspace", info.workspace.slice());
    }
}

/// A doctor check row: a level dot, a fixed-width name, then its detail
/// (design's check_row).
fn checkRow(c: *ui.Context, check: fxcli.Check) void {
    const color: ui.Color = switch (check.level) {
        .ok => t.green_900,
        .warn => t.amber_700,
        .fail => t.red_900,
    };
    const row = ui.div(c).row().wFull().h(44).px(16).gap(12).itemsCenter();
    defer row.end();
    w.dot(c, color);
    {
        const name = ui.div(c).row().w(96).itemsCenter();
        defer name.end();
        ui.text(c, check.name.slice(), .{ .size = 13, .line_height = 18, .truncate = .ellipsis, .color = t.gray_1000 });
    }
    ui.text(c, check.detail.slice(), .{ .size = 13, .line_height = 18, .truncate = .ellipsis, .color = t.gray_900 });
}

/// A path row: a fixed 96pt label, the path (home shortened to ~), and a
/// Reveal button that opens it in the file manager.
fn fileRow(c: *ui.Context, id: []const u8, label: []const u8, path: []const u8) void {
    const row = ui.div(c).row().wFull().h(48).px(16).gap(12).itemsCenter();
    defer row.end();
    {
        const name = ui.div(c).row().w(96).itemsCenter();
        defer name.end();
        ui.text(c, label, .{ .size = 13, .line_height = 18, .color = t.gray_1000 });
    }
    const shown = shortenHome(c, path);
    ui.text(c, shown, .{ .size = 12, .line_height = 16, .mono = true, .family = t.mono_family, .truncate = .ellipsis, .color = t.gray_900 });
    {
        const spacer = ui.div(c).grow();
        defer spacer.end();
    }
    if (w.button(c, id, "Reveal", false)) reveal(path);
}

/// Replaces a leading home directory with `~`, like the design's file_row.
fn shortenHome(c: *ui.Context, path: []const u8) []const u8 {
    const home = if (std.c.getenv("HOME")) |v| std.mem.span(v) else return path;
    if (home.len == 0 or path.len < home.len) return path;
    if (!std.mem.startsWith(u8, path, home)) return path;
    return c.print("~{s}", .{path[home.len..]});
}

/// Opens the path's parent in the platform file manager.
fn reveal(path: []const u8) void {
    if (path.len == 0) return;
    const io = @import("proc.zig").io();
    const argv: []const []const u8 = if (@import("builtin").os.tag == .macos)
        &.{ "open", "-R", path }
    else
        &.{ "xdg-open", path };
    _ = std.process.run(std.heap.c_allocator, io, .{ .argv = argv }) catch return;
}
