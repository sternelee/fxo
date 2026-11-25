//! fx desktop: native UI on nanoui, driven by `fx acp`.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app_view = @import("view.zig");
const engine_mod = @import("engine.zig");

pub const panic = nanoui.panic;
pub const std_options = nanoui.std_options;
pub const std_options_debug_threaded_io = std.Io.Threaded.global_single_threaded;

var g_window: ?*nanoui.Window = null;

fn wake() void {
    if (g_window) |window| window.redrawFromAnyThread();
}

pub fn main(init: nanoui.Init) void {
    const gpa = std.heap.c_allocator;
    @import("proc.zig").initFrom(init);
    _ = ui.registerFont(@embedFile("GeistMono-Regular.ttf"));

    const app = nanoui.App.create(init, .{ .name = "fx" }) catch return;
    defer app.destroy();

    var state = app_view.State.init(gpa);
    defer state.deinit();

    // fx's ACP requires an absolute cwd for session/new. Resolve the process
    // working directory before handing it to the embedded engine.
    var cwd_buf: [4096]u8 = undefined;
    const cwd: []const u8 = if (std.c.getcwd(&cwd_buf, cwd_buf.len)) |p|
        gpa.dupe(u8, std.mem.sliceTo(p, 0)) catch "."
    else
        ".";
    const args = init.args.toSlice(gpa) catch &.{};
    defer if (args.len > 0) gpa.free(args);

    var engine = engine_mod.Engine.init(gpa, cwd, wake);
    // Headless snapshots must not spawn a real agent process.
    var headless = false;
    for (args) |arg| {
        if (std.mem.indexOf(u8, arg, "--nanoui-snapshot") != null or
            std.mem.indexOf(u8, arg, "--nanoui-eval") != null) headless = true;
    }
    if (!headless) engine.start();
    defer engine.deinit();
    state.engine = &engine;

    // Settings data: background loader live, synchronous gather headless so
    // snapshots show real fx output.
    var fx_loader = @import("fxcli.zig").Loader.init(gpa, wake);
    if (headless) {
        @import("fxcli.zig").gather(gpa, &state.fx_info);
    } else {
        fx_loader.start();
        state.fx_loader = &fx_loader;
    }
    defer fx_loader.deinit();

    var folder: []const u8 = cwd;
    for (args[1..]) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) {
            folder = arg;
            break;
        }
    }
    state.addWorkspace(folder);

    // Dev-only: render a fake permission request for snapshot verification.
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--fx-preview-beside")) {
            state.newSession();
            if (state.currentSession()) |session| {
                var turn = @import("state.zig").Turn.init(gpa, "Inspect the repo and run the tests");
                turn.answer.appendSlice(gpa, "The build is green.") catch {};
                turn.status = .idle;
                turn.elapsed_ms = 9_000;
                session.turns.append(gpa, turn) catch {};
                session.status = .idle;
            }
            // A second session shown beside the first.
            const ws = &state.workspaces.items[state.folder];
            var other = @import("state.zig").Session.init(gpa, "Fix the linter");
            var turn2 = @import("state.zig").Turn.init(gpa, "What does the linter say?");
            turn2.answer.appendSlice(gpa, "Two warnings in view.zig.") catch {};
            turn2.status = .idle;
            other.turns.append(gpa, turn2) catch {};
            other.status = .waiting;
            ws.sessions.append(gpa, other) catch {};
            state.beside = .{ .ws = state.folder, .si = ws.sessions.items.len - 1 };
        }
        if (std.mem.eql(u8, arg, "--fx-preview-queued")) {
            state.newSession();
            if (state.currentSession()) |session| {
                var turn = @import("state.zig").Turn.init(gpa, "Inspect the repo and run the tests");
                turn.status = .running;
                session.turns.append(gpa, turn) catch {};
                session.status = .running;
                session.queue.append(gpa, gpa.dupe(u8, "Then update the README") catch "") catch {};
                session.queue.append(gpa, gpa.dupe(u8, "And run the linter") catch "") catch {};
            }
        }
        if (std.mem.eql(u8, arg, "--fx-preview-install")) {
            state.newSession();
            state.page = .home;
            state.agent_error = "error: Unable to spawn: FileNotFound (fx: not found)";
        }
        if (std.mem.eql(u8, arg, "--fx-preview-first-run")) {
            // No workspace at all: the first-run page.
            for (state.workspaces.items) |ws| {
                gpa.free(ws.name);
                gpa.free(ws.path);
            }
            state.workspaces.clearRetainingCapacity();
            state.page = .home;
            state.active = null;
        }
        if (std.mem.eql(u8, arg, "--fx-preview-agent-down")) {
            state.newSession();
            state.page = .home;
            state.agent_error = "fx acp exited with status 1\nthread 'main' panicked at src/main.zig:42:9\nerror: expected 2 arguments, found 3\nnote: called from src/agent/loop.zig:118";
        }
        if (std.mem.eql(u8, arg, "--fx-preview-home-approval")) {
            var p = engine_mod.Permission{};
            p.request_id = 11;
            p.setKind("execute");
            p.setQuestion("Run this command?");
            p.setDetail("zig build test");
            p.addOption("allow_once", "Allow once", "allow_once");
            p.addOption("reject_once", "Deny", "reject_once");
            state.preview_permission = p;
            state.newSession();
            // Back to home so the approval card shows above the lists.
            state.page = .home;
            if (state.currentSession()) |session| {
                var turn = @import("state.zig").Turn.init(gpa, "Explain this repo");
                turn.answer.appendSlice(gpa, "A native coding agent in Zig.") catch {};
                turn.status = .idle;
                turn.elapsed_ms = 4_200;
                session.turns.append(gpa, turn) catch {};
                session.status = .waiting;
            }
        }
        if (std.mem.eql(u8, arg, "--fx-preview-permission")) {
            var p = engine_mod.Permission{};
            p.request_id = 9;
            p.setKind("execute");
            p.setQuestion("Run this command?");
            p.setDetail("npm test -- --filter desktop");
            p.addOption("allow_once", "Allow once", "allow_once");
            p.addOption("allow_always", "Allow for this session", "allow_always");
            p.addOption("reject_once", "Reject", "reject_once");
            state.preview_permission = p;
            state.newSession();
        }
        if (std.mem.eql(u8, arg, "--fx-preview-edit-approval")) {
            var p = engine_mod.Permission{};
            p.request_id = 10;
            p.setKind("edit");
            p.setQuestion("Make this change?");
            p.setDetail("src/views/sidebar.rs");
            p.addOption("allow_once", "Allow once", "allow_once");
            p.addOption("allow_always", "Allow for this session", "allow_always");
            p.addOption("reject_once", "Reject", "reject_once");
            @import("acp_parse.zig").buildDiff(&p, "fn render_rows(&self, cx: &mut Context<Self>) {\n    let rows = self.rows.clone();\n    for row in rows.iter() {\n        list.push(row.render(cx));\n    }\n}", "fn render_rows(&self, cx: &mut Context<Self>) {\n    let workspaces = self.workspaces.read(cx);\n    for row in workspaces.iter() {\n        list.push(row.render(cx));\n    }\n}");
            state.preview_permission = p;
            state.newSession();
        }
    }

    // Dev-only: open Settings (optionally a section index) for snapshots.
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--fx-preview-settings")) {
            state.page = .settings;
        }
        if (std.mem.startsWith(u8, arg, "--fx-settings-section=")) {
            state.page = .settings;
            const value = arg["--fx-settings-section=".len..];
            // Accept a section name or its index.
            if (std.fmt.parseInt(u8, value, 10)) |idx| {
                state.settings_section = switch (idx) {
                    0 => .models,
                    1 => .behaviour,
                    2 => .mcp,
                    3 => .skills,
                    4 => .usage,
                    else => .about,
                };
            } else |_| {
                state.settings_section = if (std.mem.eql(u8, value, "models"))
                    .models
                else if (std.mem.eql(u8, value, "behaviour"))
                    .behaviour
                else if (std.mem.eql(u8, value, "mcp"))
                    .mcp
                else if (std.mem.eql(u8, value, "skills"))
                    .skills
                else if (std.mem.eql(u8, value, "usage"))
                    .usage
                else
                    .about;
            }
        }
    }

    // Dev-only: open the changes panel for snapshot verification.
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--fx-preview-changes")) {
            state.toggleChanges();
        }
    }

    // Dev-only: open a dialog or picker for snapshot verification.
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--fx-preview-dialog")) {
            state.newSession();
            state.openRename();
        }
        if (std.mem.eql(u8, arg, "--fx-preview-picker")) {
            state.newSession();
            const pk = @import("picker.zig");
            const paths = [_][]const u8{ "src/main.zig", "src/view.zig", "src/engine.zig", "README.md" };
            pk.build(&state.picker, .file, "s", &paths);
        }
        if (std.mem.eql(u8, arg, "--fx-preview-usage-menu")) {
            state.newSession();
            state.composer_menu = .usage;
            state.menu_anchor = .{ .x = 900, .y = 690 };
            if (state.currentSession()) |session| {
                var turn = @import("state.zig").Turn.init(gpa, "Explain this repo");
                turn.answer.appendSlice(gpa, "A native coding agent in Zig.") catch {};
                turn.status = .idle;
                turn.elapsed_ms = 5_000;
                session.turns.append(gpa, turn) catch {};
                session.status = .idle;
            }
        }
        if (std.mem.eql(u8, arg, "--fx-preview-menu")) {
            state.newSession();
            state.composer_menu = .mode;
            // Approximate the mode pill's position for the no-click preview.
            state.menu_anchor = .{ .x = 400, .y = 690 };
            // Give the session a turn so the transcript is not empty.
            if (state.currentSession()) |session| {
                var turn = @import("state.zig").Turn.init(gpa, "Explain this repo");
                turn.answer.appendSlice(gpa, "A native coding agent in Zig.") catch {};
                turn.status = .idle;
                turn.elapsed_ms = 5_300;
                session.turns.append(gpa, turn) catch {};
                session.status = .idle;
            }
        }
        if (std.mem.eql(u8, arg, "--fx-preview-model-menu")) {
            state.newSession();
            state.composer_menu = .model;
            state.menu_anchor = .{ .x = 760, .y = 690 };
            // Give the session a turn so the transcript is not empty.
            if (state.currentSession()) |session| {
                var turn = @import("state.zig").Turn.init(gpa, "Explain this repo");
                turn.answer.appendSlice(gpa, "A native coding agent in Zig.") catch {};
                turn.status = .idle;
                turn.elapsed_ms = 6_100;
                session.turns.append(gpa, turn) catch {};
                session.status = .idle;
            }
        }
        if (std.mem.eql(u8, arg, "--fx-preview-tabbar")) {
            state.sidebar_open = false;
            state.newSession();
            state.newSession();
            // Give the open session a turn so the transcript is not empty.
            if (state.currentSession()) |session| {
                var turn = @import("state.zig").Turn.init(gpa, "Explain this repo");
                turn.answer.appendSlice(gpa, "A native coding agent in Zig.") catch {};
                turn.status = .idle;
                turn.elapsed_ms = 8_200;
                session.turns.append(gpa, turn) catch {};
                session.status = .idle;
            }
        }
        if (std.mem.eql(u8, arg, "--fx-preview-attach-menu")) {
            state.newSession();
            state.attach_menu = true;
            state.menu_anchor = .{ .x = 400, .y = 690 };
        }
        if (std.mem.eql(u8, arg, "--fx-preview-attachments")) {
            state.newSession();
            const paths = [_][]const u8{"preview.png"};
            state.attachImages(&paths);
        }
        if (std.mem.eql(u8, arg, "--fx-preview-timeline")) {
            state.newSession();
            state.input.set("Inspect the repo and run the tests");
            state.sendPrompt();
            const T = @import("engine.zig").ToolStep;
            const session = state.currentSession().?;
            const turn = &session.turns.items[0];
            turn.thought.appendSlice(gpa, "let me look at the repo structure") catch {};
            var s1 = T{};
            s1.setId("c1");
            s1.setKind("read");
            s1.setName("read_file");
            s1.setStatus("completed");
            s1.setDetail("src/main.zig");
            var s2 = T{};
            s2.setId("c2");
            s2.setKind("execute");
            s2.setName("shell");
            s2.setStatus("completed");
            s2.setDetail("zig build test");
            s2.appendOutput("All 23 tests passed.");
            var s3 = T{};
            s3.setId("c3");
            s3.setKind("other");
            s3.setName("ask_user_question");
            s3.setStatus("completed");
            s3.setDetail("Which color should the badge use?");
            const Q = @import("acp_parse.zig").Question;
            const P = @import("acp_parse.zig");
            var q = Q{};
            q.prompt_len = P.copyBounded(&q.prompt, "Which color should the badge use?");
            q.option_lens[0] = P.copyBounded(&q.options[0], "Red");
            q.option_lens[1] = P.copyBounded(&q.options[1], "Blue");
            q.option_count = 2;
            s3.question = q;
            turn.steps[0] = s1;
            turn.steps[1] = s2;
            turn.steps[2] = s3;
            turn.step_count = 3;
            turn.answer.appendSlice(gpa, "The build is **green** and `zig build test` passes all 24 tests.\n\n- sidebar, home, thread\n- palette, changes, settings") catch {};
            // Settle the turn so the snapshot shows the folded "Worked" summary.
            turn.status = .idle;
            turn.elapsed_ms = 12_400;
            // The session settles too, so the composer shows Send, not Stop.
            session.status = .idle;
        }
    }

    // Dev-only: open the palette for snapshot verification.
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--fx-preview-palette")) {
            state.palette.open = true;
            state.palette.query.focus();
        }
    }

    const window = app.newWindow(.{
        .title = "fx",
        .width = 1120,
        .height = 760,
        .title_bar = .hidden,
        // Traffic lights centered in the 48pt sidebar header (design shell.rs).
        .traffic_lights = .{ .x = 20, .y = 24 },
        .content = .{ .view = .init(&state, app_view.view) },
    }) catch return;
    g_window = window;
    app.run() catch return;
}
