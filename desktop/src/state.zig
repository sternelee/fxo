//! UI state. Main-thread only. Worker snapshots land here via `engine`.
const std = @import("std");
const ui = @import("nanoui").ui;
const git = @import("git.zig");

pub const Status = enum { idle, waiting, running, stopped };

pub const Turn = struct {
    prompt: []const u8,
    answer: std.ArrayList(u8),
    thought: std.ArrayList(u8) = .empty,
    steps: [32]@import("engine.zig").ToolStep = undefined,
    step_count: usize = 0,
    status: Status = .running,
    elapsed_ms: u64 = 0,
    /// Image bytes sent with this prompt, shown above the bubble.
    images: std.ArrayList([]u8) = .empty,
    /// Why the turn stopped, when fx reported a non-normal reason
    /// (cancelled, max_tokens, refusal, …).
    stop_reason: []const u8 = "",

    pub fn init(alloc: std.mem.Allocator, prompt: []const u8) Turn {
        return .{ .prompt = alloc.dupe(u8, prompt) catch "", .answer = .empty };
    }
};

pub const Session = struct {
    id: ?[]const u8 = null,
    title: []const u8 = "New session",
    /// True once the user renamed it, so fx's own title stops replacing it.
    renamed: bool = false,
    turns: std.ArrayList(Turn) = .empty,
    status: Status = .idle,
    expanded: bool = false,
    /// Removed from the list but kept for the Archived tab.
    archived: bool = false,
    /// Monotonic seconds of the last activity (0 = never touched).
    updated_at: f64 = 0,
    /// Prompts typed while a turn was running, sent when it finishes.
    queue: std.ArrayList([]const u8) = .empty,

    pub fn init(alloc: std.mem.Allocator, title: []const u8) Session {
        return .{ .title = alloc.dupe(u8, title) catch "New session" };
    }

    /// "now" / "5m" / "3h" / "2d", like the design's ago().
    pub fn age(s: *const Session, c: *ui.Context) []const u8 {
        if (s.updated_at <= 0) return "";
        const secs_f = @import("nanoui").ui.clock.now() - s.updated_at;
        if (secs_f < 60) return "now";
        const secs: u64 = @intFromFloat(secs_f);
        if (secs < 3_600) return c.print("{d}m", .{secs / 60});
        if (secs < 86_400) return c.print("{d}h", .{secs / 3_600});
        return c.print("{d}d", .{secs / 86_400});
    }
};

pub const Workspace = struct {
    path: []const u8,
    name: []const u8,
    sessions: std.ArrayList(Session) = .empty,
};

pub const Page = enum { home, session, settings };

pub const State = struct {
    alloc: std.mem.Allocator,
    workspaces: std.ArrayList(Workspace) = .empty,
    folder: usize = 0,
    active: ?usize = null,
    page: Page = .home,
    sidebar_open: bool = true,
    input: ui.TextBuffer = .{},
    status_line: []const u8 = "Ready",
    agent_error: ?[]const u8 = null,
    engine: ?*@import("engine.zig").Engine = null,
    last_revision: u64 = 0,
    /// Set by the permission card; consumed by the root view after drawing.
    pending_answer: ?struct { id: i64, option: ?[]const u8 } = null,
    answer_buf: [32]u8 = undefined,
    answer_id: ?i64 = null,
    pending_clear: bool = false,
    /// Set in tests/snapshots to render the approval card without an agent.
    preview_permission: ?@import("engine.zig").Permission = null,
    /// Number of permission answers dispatched (useful for tests).
    answers_sent: usize = 0,
    palette: @import("palette.zig").Palette = .{},
    picker: @import("picker.zig").Picker = .{},
    composer_menu: ?@import("composer_menu.zig").Menu = null,
    /// Screen point of the pill that opened the composer menu (its bottom-center).
    menu_anchor: @import("nanoui").ui.Point = .{},
    /// Set when the Behaviour page's Add folder button asks for a picker.
    pick_extra_folder: bool = false,
    /// The MCP page's inline add form: open, and its two fields.
    mcp_adding: bool = false,
    mcp_name: ui.TextBuffer = .{},
    mcp_address: ui.TextBuffer = .{},
    /// Why the last add attempt failed, shown under the form.
    mcp_add_error: ?[]const u8 = null,
    /// Which MCP server's overflow menu is open.
    mcp_menu: ?usize = null,
    /// The workspace's AGENTS.md, loaded when the Behaviour page opens and
    /// written back as it is edited (design's instructions field).
    instructions: @import("nanoui").ui.TextBuffer = .{},
    /// True once instructions were read from disk, so the field is not
    /// refilled over what the user typed.
    instructions_loaded: bool = false,
    /// Attached image bytes (PNG/JPEG/GIF/WebP), shown as thumbnails and sent with a prompt.
    attachments: std.ArrayList([]u8) = .empty,
    dialog: ?@import("dialog.zig").Dialog = null,
    rename_input: ui.TextBuffer = .{},
    pending_dialog_confirm: bool = false,
    /// Set by the palette; applied at the end of the frame.
    pending_action: ?@import("palette.zig").Action = null,
    home_tab: @import("home.zig").HomeTab = .recent,
    settings_section: @import("settings.zig").Section = .models,
    notify_muted: bool = false,
    fast_mode: bool = false,
    light_theme: bool = false,
    show_all_sessions: bool = false,
    fx_info: @import("fxcli.zig").Info = .{},
    fx_loader: ?*@import("fxcli.zig").Loader = null,
    changes_open: bool = false,
    changes: @import("git.zig").Snapshot = undefined,
    changes_diff: std.ArrayList(@import("git.zig").DiffLine) = .empty,
    changes_open_file: ?[]const u8 = null,
    changes_full: bool = false,
    /// Turns whose step list the user expanded (design's session.expanded).
    expanded_turns: [64]usize = undefined,
    expanded_len: usize = 0,
    /// The session row whose ⋯ menu is open (workspace, session), if any.
    row_menu: ?struct { ws: usize, si: usize } = null,
    /// The tab bar's folder switcher menu, when open.
    folders_menu_open: bool = false,
    /// The model menu's search query.
    model_query: ui.TextBuffer = .{},
    /// The skills page's filter query.
    skill_filter: ui.TextBuffer = .{},
    /// When true the Skills page shows every skill instead of four per group.
    skills_all: bool = false,
    /// The composer attach menu, when open.
    attach_menu: bool = false,
    /// The usage page's period: "today", "7d" or "month".
    usage_period: []const u8 = "month",
    /// A second session shown beside the main one (workspace, session).
    beside: ?struct { ws: usize, si: usize } = null,

    pub fn isExpanded(s: *const State, turn: usize) bool {
        for (s.expanded_turns[0..s.expanded_len]) |v| {
            if (v == turn) return true;
        }
        return false;
    }

    pub fn toggleTurn(s: *State, turn: usize) void {
        for (s.expanded_turns[0..s.expanded_len], 0..) |v, i| {
            if (v == turn) {
                var j = i;
                while (j + 1 < s.expanded_len) : (j += 1) s.expanded_turns[j] = s.expanded_turns[j + 1];
                s.expanded_len -= 1;
                return;
            }
        }
        if (s.expanded_len < s.expanded_turns.len) {
            s.expanded_turns[s.expanded_len] = turn;
            s.expanded_len += 1;
        }
    }

    pub fn init(alloc: std.mem.Allocator) State {
        return .{ .alloc = alloc, .changes = @import("git.zig").Snapshot.init(alloc) };
    }

    pub fn deinit(s: *State) void {
        s.input.deinit();
        s.model_query.deinit();
        s.skill_filter.deinit();
        s.rename_input.deinit();
        for (s.attachments.items) |bytes| s.alloc.free(bytes);
        s.attachments.deinit(s.alloc);
        s.palette.deinit();
        s.changes.deinit();
        freeDiff(s);
        for (s.workspaces.items) |*w| {
            for (w.sessions.items) |*t| {
                for (t.turns.items) |*turn| {
                    turn.answer.deinit(s.alloc);
                    turn.thought.deinit(s.alloc);
                    s.alloc.free(turn.prompt);
                }
                t.turns.deinit(s.alloc);
                s.alloc.free(t.title);
            }
            w.sessions.deinit(s.alloc);
            s.alloc.free(w.name);
            s.alloc.free(w.path);
        }
        s.workspaces.deinit(s.alloc);
    }

    pub fn addWorkspace(s: *State, path: []const u8) void {
        var base = std.fs.path.basename(path);
        if (base.len == 0 or std.mem.eql(u8, base, ".") or std.mem.eql(u8, base, "/")) base = "workspace";
        s.workspaces.append(s.alloc, .{
            .path = s.alloc.dupe(u8, path) catch return,
            .name = s.alloc.dupe(u8, base) catch return,
        }) catch return;
        s.folder = s.workspaces.items.len - 1;
        s.page = .home;
        s.active = null;
        // Load git status for the new folder right away, so the header's diff
        // counts and the changes panel are correct without toggling it first.
        @import("git.zig").refresh(&s.changes, s.workspaces.items[s.folder].path);
    }

    pub fn newSession(s: *State) void {
        if (s.workspaces.items.len == 0) return;
        const w = &s.workspaces.items[s.folder];
        w.sessions.append(s.alloc, Session.init(s.alloc, "New session")) catch return;
        s.active = w.sessions.items.len - 1;
        w.sessions.items[s.active.?].updated_at = ui.clock.now();
        s.page = .session;
    }

    /// Starts a session in a named workspace, so the sidebar's + creates one
    /// in the project it sits beside (design's new_session_in).
    pub fn newSessionIn(s: *State, wi: usize) void {
        if (wi >= s.workspaces.items.len) return;
        const w = &s.workspaces.items[wi];
        w.sessions.append(s.alloc, Session.init(s.alloc, "New session")) catch return;
        s.folder = wi;
        s.active = w.sessions.items.len - 1;
        w.sessions.items[s.active.?].updated_at = ui.clock.now();
        s.page = .session;
    }

    pub fn selectSession(s: *State, index: usize) void {
        const w = &s.workspaces.items[s.folder];
        if (index >= w.sessions.items.len) return;
        s.active = index;
        s.page = .session;
    }

    pub fn currentSession(s: *State) ?*Session {
        if (s.page != .session) return null;
        const idx = s.active orelse return null;
        const w = &s.workspaces.items[s.folder];
        if (idx >= w.sessions.items.len) return null;
        return &w.sessions.items[idx];
    }

    pub fn sendPrompt(s: *State) void {
        const text = std.mem.trim(u8, s.input.text(), " \t\r\n");
        if (text.len == 0) return;
        if (s.workspaces.items.len == 0) s.addWorkspace(".");
        if (s.currentSession() == null) s.newSession();
        const session = s.currentSession() orelse return;
        // While a turn runs, the prompt queues instead of interrupting it.
        if (session.status == .running) {
            session.queue.append(s.alloc, s.alloc.dupe(u8, text) catch return) catch return;
            s.input.clear();
            s.status_line = "Queued";
            return;
        }
        session.turns.append(s.alloc, Turn.init(s.alloc, text)) catch return;
        // Hand the composer's attachments to this turn so they render above
        // the prompt bubble (design's thumbnails).
        if (s.attachments.items.len > 0) {
            const t = &session.turns.items[session.turns.items.len - 1];
            t.images = s.attachments;
            s.attachments = .empty;
        }
        session.status = .running;
        session.updated_at = ui.clock.now();
        // `text` points into the composer's buffer, so copy it before clearing
        // the input; otherwise the engine is handed an empty prompt.
        const outgoing = s.alloc.dupe(u8, text) catch {
            s.input.clear();
            return;
        };
        s.input.clear();
        if (s.engine) |engine| {
            engine.send(outgoing, session.id);
        }
        s.alloc.free(outgoing);
        s.status_line = "Working";
    }

    /// Opens a session beside the current one (design's open_beside).
    pub fn openBeside(s: *State, ws: usize, si: usize) void {
        if (ws >= s.workspaces.items.len) return;
        if (si >= s.workspaces.items[ws].sessions.items.len) return;
        s.beside = .{ .ws = ws, .si = si };
    }

    /// Swaps the beside session into the main pane and closes the split.
    pub fn swapBeside(s: *State) void {
        const at = s.beside orelse return;
        s.folder = at.ws;
        s.active = at.si;
        s.page = .session;
        s.beside = null;
    }

    /// Closes the open diff and returns to the file list.
    pub fn closeChange(s: *State) void {
        freeDiff(s);
        s.changes_open_file = null;
        s.changes_full = false;
    }

    /// Sends the next queued prompt once the session is idle again.
    pub fn flushQueue(s: *State) void {
        const session = s.currentSession() orelse return;
        if (session.status == .running or session.queue.items.len == 0) return;
        const next = session.queue.orderedRemove(0);
        defer s.alloc.free(next);
        session.turns.append(s.alloc, Turn.init(s.alloc, next)) catch return;
        session.status = .running;
        session.updated_at = ui.clock.now();
        if (s.engine) |engine| engine.send(next, session.id);
        s.status_line = "Working";
    }

    /// Drops one queued prompt by index.
    pub fn dropQueued(s: *State, index: usize) void {
        const session = s.currentSession() orelse return;
        if (index >= session.queue.items.len) return;
        const dropped = session.queue.orderedRemove(index);
        s.alloc.free(dropped);
    }

    /// Recomputes the @ / / picker from the current draft.
    pub fn updatePicker(s: *State) void {
        const trig = @import("picker.zig").trigger(s.input.text()) orelse {
            s.picker = .{};
            return;
        };
        if (s.workspaces.items.len == 0) return;
        const cwd = s.workspaces.items[s.folder].path;
        var candidates: [64][]const u8 = undefined;
        var count: usize = 0;
        if (trig.kind == .file) {
            const io = @import("proc.zig").io();
            const argv = [_][]const u8{ "git", "ls-files", "--cached", "--others", "--exclude-standard" };
            if (std.process.run(s.alloc, io, .{ .argv = &argv, .cwd = .{ .path = cwd } })) |r| {
                defer s.alloc.free(r.stderr);
                defer s.alloc.free(r.stdout);
                var lines = std.mem.splitScalar(u8, r.stdout, '\n');
                while (lines.next()) |line| {
                    if (count >= candidates.len) break;
                    const trimmed = std.mem.trim(u8, line, "\r");
                    if (trimmed.len == 0) continue;
                    candidates[count] = trimmed;
                    count += 1;
                }
                @import("picker.zig").build(&s.picker, .file, trig.query, candidates[0..count]);
                return;
            } else |_| {}
        } else {
            // Skills: scan .fx/skills and ~/.fx/skills for SKILL.md dirs.
            const roots = [_][]const u8{ ".fx/skills", ".agents/skills", ".claude/skills" };
            for (roots) |root| {
                const dio = @import("proc.zig").io();
                var dir = std.Io.Dir.cwd().openDir(dio, root, .{}) catch continue;
                defer dir.close(dio);
                var it = dir.iterate();
                while (it.next(dio) catch null) |entry| {
                    if (count >= candidates.len) break;
                    if (entry.kind != .directory) continue;
                    candidates[count] = s.alloc.dupe(u8, entry.name) catch continue;
                    count += 1;
                }
            }
        }
        @import("picker.zig").build(&s.picker, trig.kind, trig.query, candidates[0..count]);
    }

    /// Applies the selected picker item into the draft.
    pub fn acceptPicker(s: *State) void {
        if (s.picker.count == 0) return;
        const item = s.picker.items[s.picker.selected];
        const insert = item.insertSlice();
        const draft = s.input.text();
        const next = if (s.picker.kind == .skill)
            s.alloc.dupe(u8, insert) catch return
        else blk: {
            const at = std.mem.lastIndexOfScalar(u8, draft, '@') orelse draft.len;
            break :blk std.fmt.allocPrint(s.alloc, "{s}{s}", .{ draft[0..at], insert }) catch return;
        };
        defer s.alloc.free(next);
        s.input.set(next);
        s.picker = .{};
    }

    pub fn openRename(s: *State) void {
        const session = s.currentSession() orelse return;
        var d = @import("dialog.zig").Dialog{ .kind = .rename };
        d.setTitle("Rename session");
        d.setNote("Only this app shows the new name. fx keeps its own.");
        d.setTarget(session.title);
        s.rename_input.set(session.title);
        s.dialog = d;
    }

    pub fn openRemove(s: *State) void {
        const session = s.currentSession() orelse return;
        var d = @import("dialog.zig").Dialog{ .kind = .remove };
        d.setTitle("Remove this session?");
        const note = std.fmt.allocPrint(s.alloc, "“{s}” moves to Archived on the home screen. The files it changed are not touched.", .{session.title}) catch "";
        defer if (note.len > 0) s.alloc.free(note);
        d.setNote(note);
        d.setTarget(session.title);
        s.dialog = d;
    }

    pub fn confirmDialog(s: *State) void {
        const d = s.dialog orelse return;
        switch (d.kind) {
            .rename => {
                const name = std.mem.trim(u8, s.rename_input.text(), " \t\r\n");
                if (name.len > 0) {
                    if (s.currentSession()) |session| {
                        s.alloc.free(session.title);
                        session.title = s.alloc.dupe(u8, name) catch session.title;
                        // A name the user chose outranks the one fx reports.
                        session.renamed = true;
                    }
                }
            },
            .remove => {
                // Design: the session moves to Archived, its files untouched.
                if (s.active) |idx| {
                    if (s.workspaces.items.len > 0) {
                        const w = &s.workspaces.items[s.folder];
                        if (idx < w.sessions.items.len) {
                            w.sessions.items[idx].archived = true;
                            w.sessions.items[idx].status = .idle;
                        }
                    }
                }
                s.page = .home;
                s.active = null;
            },
            .full_access => {
                s.status_line = "Full access enabled";
                s.fx_info.permission_mode.set("full-access");
                if (s.engine) |engine| engine.setConfigOption("mode", "full-access");
            },
            .discard => {
                // Actually revert the file, then refresh the panel.
                s.discardChange(d.targetSlice());
            },
        }
        s.dialog = null;
    }

    /// Attaches image files (read from disk), bounded to 8 files and 3.75 MiB each.
    pub fn attachImages(s: *State, paths: []const []const u8) void {
        const max_files = 8;
        const max_bytes = 3_932_160;
        for (paths) |path| {
            if (s.attachments.items.len >= max_files) break;
            const ext = std.fs.path.extension(path);
            if (!std.ascii.eqlIgnoreCase(ext, ".png") and !std.ascii.eqlIgnoreCase(ext, ".jpg") and
                !std.ascii.eqlIgnoreCase(ext, ".jpeg") and !std.ascii.eqlIgnoreCase(ext, ".gif") and
                !std.ascii.eqlIgnoreCase(ext, ".webp")) continue;
            const dio = @import("proc.zig").io();
            var file = std.Io.Dir.cwd().openFile(dio, path, .{}) catch continue;
            defer file.close(dio);
            var read_buf: [8192]u8 = undefined;
            var reader = file.reader(dio, &read_buf);
            var content: std.ArrayList(u8) = .empty;
            defer content.deinit(s.alloc);
            reader.interface.appendRemaining(s.alloc, &content, .limited(max_bytes)) catch continue;
            const bytes = content.toOwnedSlice(s.alloc) catch continue;
            s.attachments.append(s.alloc, bytes) catch s.alloc.free(bytes);
        }
    }

    /// Writes a global default via `fx config set` (fire-and-forget, bounded).
    pub fn setConfigDefault(key: []const u8, value: []const u8) void {
        const io = @import("proc.zig").io();
        const argv = [_][]const u8{ "fx", "config", "set", key, value };
        const result = std.process.run(std.heap.c_allocator, io, .{ .argv = &argv }) catch return;
        std.heap.c_allocator.free(result.stdout);
        std.heap.c_allocator.free(result.stderr);
    }

    /// Opens the native folder picker and adds the chosen folder as a workspace.
    pub fn openFolderDialog(s: *State) void {
        const nanoui = @import("nanoui");
        const picked = nanoui.dialog.open(s.alloc, .{
            .title = "Add a folder",
            .directories = true,
            .files = false,
            .multiple = false,
        }) catch return;
        defer if (picked) |paths| nanoui.dialog.freePaths(s.alloc, paths);
        if (picked) |paths| {
            if (paths.len > 0) s.addWorkspace(paths[0]);
        }
    }

    /// Reads the workspace's AGENTS.md into the instructions field.
    pub fn loadInstructions(s: *State) void {
        if (s.instructions_loaded) return;
        s.instructions_loaded = true;
        const dir = s.workspacePath() orelse return;
        const io = @import("proc.zig").io();
        const path = std.fmt.allocPrint(s.alloc, "{s}/AGENTS.md", .{dir}) catch return;
        defer s.alloc.free(path);
        var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return;
        defer file.close(io);
        var buf: [65536]u8 = undefined;
        var reader = file.reader(io, &buf);
        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(s.alloc);
        reader.interface.appendRemaining(s.alloc, &content, .limited(1 << 20)) catch return;
        s.instructions.set(content.items);
    }

    /// Writes the instructions field back to the workspace's AGENTS.md.
    pub fn saveInstructions(s: *State) void {
        const dir = s.workspacePath() orelse return;
        const body = s.instructions.text();
        if (body.len == 0) return;
        const io = @import("proc.zig").io();
        const path = std.fmt.allocPrint(s.alloc, "{s}/AGENTS.md", .{dir}) catch return;
        defer s.alloc.free(path);
        var file = std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true }) catch return;
        defer file.close(io);
        var buf: [4096]u8 = undefined;
        var writer = file.writer(io, &buf);
        writer.interface.writeAll(body) catch return;
        writer.interface.flush() catch return;
    }

    /// Registers an MCP server with fx (`fx mcp add NAME URL`), then reloads
    /// the list so the new row appears.
    /// Runs an MCP command (`fx mcp <verb> NAME`) and refreshes the list.
    pub fn runMcpCommand(s: *State, verb: []const u8, name: []const u8) void {
        const fxcli = @import("fxcli.zig");
        _ = fxcli.mcpCommand(s.alloc, verb, name);
        s.mcp_menu = null;
        fxcli.gather(s.alloc, &s.fx_info);
    }

    /// Runs an fx command in the user's Terminal app, the way fx-ui's
    /// in_terminal helper does for Update fx and similar actions.
    pub fn runInTerminal(command: []const u8) void {
        const script = std.fmt.allocPrint(std.heap.c_allocator, "tell application \"Terminal\"\n activate\n do script \"fx {s}\"\nend tell", .{command}) catch return;
        defer std.heap.c_allocator.free(script);
        const io = @import("proc.zig").io();
        var child = std.process.spawn(io, .{
            .argv = &.{ "osascript", "-e", script },
            .stdin = .inherit,
            .stdout = .inherit,
            .stderr = .inherit,
        }) catch return;
        // Let osascript finish handing the command to Terminal.
        _ = child.wait(io) catch {};
    }

    pub fn addMcpServer(s: *State) void {
        const name = std.mem.trim(u8, s.mcp_name.text(), " \t\r\n");
        const address = std.mem.trim(u8, s.mcp_address.text(), " \t\r\n");
        if (name.len == 0 or address.len == 0) return;
        const fxcli = @import("fxcli.zig");
        if (fxcli.addMcpServer(s.alloc, name, address)) {
            s.mcp_adding = false;
            s.mcp_name.clear();
            s.mcp_address.clear();
            s.mcp_add_error = null;
            fxcli.gather(s.alloc, &s.fx_info);
        } else {
            s.mcp_add_error = "fx refused the server; check the name and address";
        }
    }

    /// Adds a directory to fx's extra folders, which the agent may reach as
    /// well as the primary workspace (`fx workspace add`).
    pub fn addExtraFolder(s: *State) void {
        const nanoui = @import("nanoui");
        const picked = nanoui.dialog.open(s.alloc, .{
            .title = "Add an extra folder",
            .directories = true,
            .files = false,
            .multiple = false,
        }) catch return;
        defer if (picked) |paths| nanoui.dialog.freePaths(s.alloc, paths);
        if (picked) |paths| {
            if (paths.len == 0) return;
            const fxcli = @import("fxcli.zig");
            const cwd = s.workspacePath() orelse return;
            if (!fxcli.addWorkspaceDir(s.alloc, cwd, paths[0])) return;
            fxcli.gather(s.alloc, &s.fx_info);
            // Keep the background snapshot in step so it cannot replace the
            // freshly read list with an older one on the next frame.
            if (s.fx_loader) |loader| loader.request();
        }
    }

    pub fn toggleChanges(s: *State) void {
        s.changes_open = !s.changes_open;
        if (s.changes_open and s.workspaces.items.len > 0) {
            @import("git.zig").refresh(&s.changes, s.workspaces.items[s.folder].path);
        }
    }

    fn workspacePath(s: *State) ?[]const u8 {
        if (s.workspaces.items.len == 0) return null;
        return s.workspaces.items[s.folder].path;
    }

    /// Stage/unstage one file, then refresh (design's stage_toggle).
    pub fn stageToggle(s: *State, path: []const u8, staged: bool) void {
        const cwd = s.workspacePath() orelse return;
        const ok = if (staged) git.unstage(cwd, path) else git.stage(cwd, path);
        if (!ok) {
            s.status_line = "git failed";
            return;
        }
        git.refresh(&s.changes, cwd);
    }

    /// Discard one file after the confirm dialog (design's discard).
    pub fn discardChange(s: *State, path: []const u8) void {
        const cwd = s.workspacePath() orelse return;
        if (!git.discard(cwd, path)) {
            s.status_line = "git failed";
            return;
        }
        s.status_line = "Changes discarded";
        if (s.changes_open_file) |p| {
            if (std.mem.eql(u8, p, path)) {
                freeDiff(s);
                s.changes_open_file = null;
            }
        }
        git.refresh(&s.changes, cwd);
    }

    /// Stage or unstage every file in a group (design's Stage all / Unstage all).
    pub fn stageAll(s: *State, staged: bool) void {
        const cwd = s.workspacePath() orelse return;
        var ok = true;
        for (s.changes.changes.items) |ch| {
            if (ch.staged != staged) continue;
            if (staged) {
                ok = git.unstage(cwd, ch.path) and ok;
            } else {
                ok = git.stage(cwd, ch.path) and ok;
            }
        }
        if (!ok) s.status_line = "git failed";
        git.refresh(&s.changes, cwd);
    }

    pub fn openChange(s: *State, path: []const u8) void {
        freeDiff(s);
        s.changes_open_file = s.alloc.dupe(u8, path) catch null;
        s.changes_full = false;
        if (s.workspaces.items.len == 0) return;
        const cwd = s.workspaces.items[s.folder].path;
        const git_mod = @import("git.zig");
        const argv_unstaged = [_][]const u8{ "git", "diff", "--", path };
        const argv_staged = [_][]const u8{ "git", "diff", "--cached", "--", path };
        var text: ?[]u8 = null;
        var staged = false;
        for (s.changes.changes.items) |ch| {
            if (std.mem.eql(u8, ch.path, path)) {
                staged = ch.staged;
                break;
            }
        }
        const io = @import("proc.zig").io();
        const result = if (staged)
            std.process.run(s.alloc, io, .{ .argv = &argv_staged, .cwd = .{ .path = cwd } }) catch null
        else
            std.process.run(s.alloc, io, .{ .argv = &argv_unstaged, .cwd = .{ .path = cwd } }) catch null;
        if (result) |r| {
            s.alloc.free(r.stderr);
            text = r.stdout;
        }
        if (text) |body| {
            defer s.alloc.free(body);
            s.changes_diff = git_mod.parseUnified(s.alloc, body) catch .empty;
        }
    }
};

fn freeDiff(s: *State) void {
    @import("git.zig").freeLines(s.alloc, &s.changes_diff);
    if (s.changes_open_file) |p| s.alloc.free(p);
    s.changes_open_file = null;
}
