//! Settings page tests: the About page's Files group, the Models page's
//! account rows, and the fx status fields they read. Headless, no fx process.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const view = @import("view.zig");
const fixture = @import("tests.zig").fixture;

test "about page lists the fx home and workspace paths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .settings;
    s.settings_section = .about;
    // Build the paths from the real HOME so the `~` shortening applies.
    const home = if (std.c.getenv("HOME")) |v| std.mem.span(v) else "/tmp";
    const fx_home = try std.fmt.allocPrint(alloc, "{s}/.fx", .{home});
    const workspace = try std.fmt.allocPrint(alloc, "{s}/project", .{home});
    s.fx_info.fx_home.set(fx_home);
    s.fx_info.workspace.set(workspace);
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Files"));
    try std.testing.expect(t.hasText("fx settings"));
    try std.testing.expect(t.hasText("Workspace"));
    // The paths come from fx status, with the home prefix shortened to ~.
    try std.testing.expect(t.hasText("~/.fx"));
    try std.testing.expect(t.hasText("~/project"));
    try std.testing.expect(t.hasText("Reveal"));
}

test "models page shows account rows with their state and actions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .settings;
    s.settings_section = .models;
    s.fx_info.loaded = true;
    s.fx_info.provider.set("magpie");
    s.fx_info.model.set("group/auto");
    s.fx_info.auth.set("configured provider");
    s.fx_info.providers[0].set("magpie");
    s.fx_info.providers[1].set("codex");
    s.fx_info.provider_count = 2;

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    // Both accounts are listed; the default one says so, the other offers
    // "Make default".
    try std.testing.expect(t.hasText("magpie"));
    try std.testing.expect(t.hasText("codex"));
    try std.testing.expect(t.hasText("configured provider · new sessions start here"));
    try std.testing.expect(t.hasText("Make default"));
    try std.testing.expect(t.hasText("Sign out"));
    // Choosing the other account records the new default.
    try t.clickText("Make default");
    t.settle(0.1);
    try std.testing.expectEqualStrings("codex", s.fx_info.provider.slice());
}

test "skills page lists skills with a filter and Open buttons" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .settings;
    s.settings_section = .skills;
    try s.fx_info.skills.append(alloc, .{});
    s.fx_info.skills.items[0].name.set("technical-writer");
    s.fx_info.skills.items[0].description.set("Write and edit prose");
    s.fx_info.skills.items[0].source.set(".fx");
    s.fx_info.skills.items[0].path.set("/example/.fx/skills/technical-writer");
    try s.fx_info.skills.append(alloc, .{});
    s.fx_info.skills.items[1].name.set("pdf");
    s.fx_info.skills.items[1].description.set("Read and cite PDFs");
    s.fx_info.skills.items[1].source.set(".fx");
    s.fx_info.skills.items[1].path.set("/example/.fx/skills/pdf");
    s.fx_info.skill_count = 2;
    // Keep the skills out of the workspace so they land in the Yours group.
    if (s.workspaces.items.len > 0) s.workspaces.items[0].path = "/workspace/other";

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    // The design groups skills into This project / Yours, each with a
    // counted header showing the harness folder.
    try std.testing.expect(t.hasText("Yours"));
    try std.testing.expect(t.hasText("/technical-writer"));
    try std.testing.expect(t.hasText("Write and edit prose"));
    try std.testing.expect(t.hasText("/pdf"));
    try std.testing.expect(t.hasText("Open"));
    try std.testing.expect(t.hasText("~/.fx/skills"));

    // Filtering narrows the list to the matching skill.
    s.skill_filter.set("pdf");
    t.settle(0.2);
    try std.testing.expect(t.hasText("/pdf"));
    try std.testing.expect(!t.hasText("/technical-writer"));
}

test "behaviour page lists always-allowed rules with a badge" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .settings;
    s.settings_section = .behaviour;
    s.fx_info.rules[0].set("Bash(git status:*)");
    s.fx_info.rules[1].set("Edit(src/**)");
    s.fx_info.rule_count = 2;

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Always allowed"));
    try std.testing.expect(t.hasText("Bash(git status:*)"));
    try std.testing.expect(t.hasText("Edit(src/**)"));
    try std.testing.expect(t.hasText("Added when you choose Always allow on an approval."));
}

test "a settings select anchors its menu on the row" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .settings;
    s.settings_section = .models;
    s.fx_info.loaded = true;
    s.fx_info.model.set("group/auto");
    s.fx_info.permission_mode.set("ask");

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    // The Model row's trigger sits in the content column, so its anchor is
    // inside the window rather than at a hardcoded offset.
    try t.clickText("Model");
    t.settle(0.1);
    try std.testing.expect(s.composer_menu == .model);
    try std.testing.expect(s.menu_anchor.x > 0 and s.menu_anchor.x < 1120);
    try std.testing.expect(s.menu_anchor.y > 0 and s.menu_anchor.y < 760);
}

test "the usage page switches period" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .settings;
    s.settings_section = .usage;
    s.fx_info.loaded = true;
    s.fx_info.usage_source.set("ai_gateway");
    s.fx_info.usage_status.set("ok");
    s.fx_info.spend = 1.25;
    s.fx_info.request_count = 9;
    s.fx_info.total_tokens = 12345;

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    // All three periods are offered; Month is the default.
    try std.testing.expect(t.hasText("Today"));
    try std.testing.expect(t.hasText("7 days"));
    try std.testing.expect(t.hasText("Month"));
    try std.testing.expectEqualStrings("month", s.usage_period);
    // The tiles read fx's numbers.
    try std.testing.expect(t.hasText("$1.25"));
    try std.testing.expect(t.hasText("12.3K"));

    // Choosing 7 days records the period.
    try t.clickText("7 days");
    t.settle(0.1);
    try std.testing.expectEqualStrings("7d", s.usage_period);
}

test "about page lists each doctor check" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .settings;
    s.settings_section = .about;
    s.fx_info.loaded = true;
    // The shape fx doctor really prints.
    @import("fxcli_parse.zig").parseDoctor(&s.fx_info,
        \\[doctor] version=0.0.17
        \\[ok] workspace: using workspace /example/project
        \\[ok] install: fx 0.0.17 at /usr/local/bin/fx
        \\[warn] session: diagnostics truncated
        \\[fail] auth: missing
    );
    try std.testing.expectEqual(@as(usize, 2), s.fx_info.doctor_ok);
    try std.testing.expectEqual(@as(usize, 1), s.fx_info.doctor_warn);
    try std.testing.expectEqual(@as(usize, 1), s.fx_info.doctor_fail);
    try std.testing.expectEqual(@as(usize, 4), s.fx_info.check_count);
    try std.testing.expectEqualStrings("workspace", s.fx_info.checks[0].name.slice());
    try std.testing.expectEqualStrings("using workspace /example/project", s.fx_info.checks[0].detail.slice());
    // The [warn] prefix is six characters, not four: its name must not keep
    // a stray "n]".
    try std.testing.expectEqualStrings("session", s.fx_info.checks[2].name.slice());
    try std.testing.expectEqualStrings("diagnostics truncated", s.fx_info.checks[2].detail.slice());

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Health"));
    try std.testing.expect(t.hasText("Run again"));
    try std.testing.expect(t.hasText("workspace"));
    try std.testing.expect(t.hasText("using workspace /example/project"));
    try std.testing.expect(t.hasText("missing"));
}

test "an mcp row shows the failure reason and the address" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .settings;
    s.settings_section = .mcp;
    s.fx_info.loaded = true;
    // One healthy server with an address, one failed with a reason.
    s.fx_info.servers[0].name.set("nanomcp");
    s.fx_info.servers[0].status.set("ready");
    s.fx_info.servers[0].address.set("http://127.0.0.1:7331/mcp");
    s.fx_info.servers[0].tools = 380;
    s.fx_info.servers[1].name.set("broken");
    s.fx_info.servers[1].status.set("failed");
    s.fx_info.servers[1].error_msg.set("connection refused");
    s.fx_info.server_count = 2;

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("nanomcp"));
    try std.testing.expect(t.hasText("http://127.0.0.1:7331/mcp"));
    try std.testing.expect(t.hasText("380 tools"));
    try std.testing.expect(t.hasText("broken"));
    // The failure reason replaces the address, so the row says what is wrong.
    try std.testing.expect(t.hasText("connection refused"));
}

test "the behaviour page lists extra folders and its add row" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .settings;
    s.settings_section = .behaviour;
    s.fx_info.loaded = true;
    s.fx_info.workspace.set("/Users/example/project");
    s.fx_info.extra_dirs[0].set("/Users/example/other");
    s.fx_info.extra_count = 1;
    s.fx_info.extra_limit = 16;

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Extra folders"));
    try std.testing.expect(t.hasText("/Users/example/other"));
    try std.testing.expect(t.hasText("Add another"));
    try std.testing.expect(t.hasText("fx reaches these as well as /Users/example/project"));
}

test "an empty extra folder list says only this folder" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .settings;
    s.settings_section = .behaviour;
    s.fx_info.loaded = true;
    s.fx_info.workspace.set("/Users/example/project");

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Only this folder"));
    try std.testing.expect(t.hasText("Add folder…"));
}

test "workspace json fills the primary directory and the extras" {
    const fxcli = @import("fxcli.zig");
    var info: fxcli.Info = .{};
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"kind":"workspace","action":"list","changed":false,"primary_directory":"/Users/example/project","saved_suppressed":false,"limit":16,"additional_directories":["/a","/b"]}
    , .{});
    defer parsed.deinit();
    fxcli.parseWorkspace(&info, parsed.value);
    try std.testing.expectEqualStrings("/Users/example/project", info.workspace.slice());
    try std.testing.expectEqual(@as(usize, 2), info.extra_count);
    try std.testing.expectEqualStrings("/a", info.extra_dirs[0].slice());
    try std.testing.expectEqualStrings("/b", info.extra_dirs[1].slice());
    try std.testing.expectEqual(@as(usize, 16), info.extra_limit);
}

test "the behaviour page carries the instructions field" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .settings;
    s.settings_section = .behaviour;
    s.fx_info.loaded = true;
    s.instructions_loaded = true; // no disk read in a test
    s.instructions.set("Prefer small diffs.");

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Instructions"));
    try std.testing.expect(t.hasText("Prefer small diffs."));
    try std.testing.expect(t.hasText("Added to every new session, after fx's own instructions."));
}

test "skills fold to four per group until Show more" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .settings;
    s.settings_section = .skills;
    s.fx_info.loaded = true;
    for (0..6) |i| {
        try s.fx_info.skills.append(alloc, .{});
        const sk = &s.fx_info.skills.items[i];
        sk.name.set(std.fmt.allocPrint(alloc, "skill-{d}", .{i}) catch "");
        sk.description.set("A skill");
        sk.source.set(".claude");
        sk.path.set(std.fmt.allocPrint(alloc, "/home/example/.claude/skills/skill-{d}", .{i}) catch "");
    }
    s.fx_info.skill_count = 6;

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Yours"));
    try std.testing.expect(t.hasText("Show 2 more"));
    try std.testing.expect(t.hasText("6"));
    // Clicking Show more reveals every skill.
    try t.clickText("Show 2 more");
    t.settle(0.2);
    try std.testing.expect(s.skills_all);
    try std.testing.expect(t.hasText("/skill-5"));
}

test "about hero shows the fx version and channel line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .settings;
    s.settings_section = .about;
    s.fx_info.loaded = true;
    s.fx_info.doctor_version.set("0.0.18");
    s.fx_info.channel.set("stable");
    s.fx_info.build.set("6196071b3c1b");

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("fx 0.0.18"));
    try std.testing.expect(t.containsText("Stable channel"));
    try std.testing.expect(t.containsText("build 6196071"));
    try std.testing.expect(t.containsText("desktop 0.0.17"));
    try std.testing.expect(t.hasText("Update fx"));
}

test "an mcp row has an overflow menu" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .settings;
    s.settings_section = .mcp;
    s.fx_info.loaded = true;
    s.fx_info.servers[0].name.set("nanomcp");
    s.fx_info.servers[0].status.set("ready");
    s.fx_info.servers[0].address.set("http://127.0.0.1:7331/mcp");
    s.fx_info.server_count = 1;

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("nanomcp"));
    // Opening the overflow menu shows Check now and Remove.
    s.mcp_menu = 0;
    s.menu_anchor = .{ .x = 900, .y = 300 };
    t.settle(0.2);
    try std.testing.expect(t.hasText("Check now"));
    try std.testing.expect(t.hasText("Remove"));
}

test "behaviour rows keep labels left and controls right" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .settings;
    s.settings_section = .behaviour;
    s.fx_info.loaded = true;
    s.instructions_loaded = true;
    s.instructions.set("Prefer small diffs.");

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    // All three labels render; the toggles sit in their own trailing slots
    // and the instructions area carries an inset.
    try std.testing.expect(t.hasText("Fast mode"));
    try std.testing.expect(t.hasText("Notify me"));
    try std.testing.expect(t.hasText("Instructions"));
    try std.testing.expect(t.hasText("Prefer small diffs."));
    // The toggles render as controls in the trailing slot of each row.
    try std.testing.expect(t.hasText("Fast mode"));
    try std.testing.expect(t.hasText("Quicker answers on models that offer it"));
}
