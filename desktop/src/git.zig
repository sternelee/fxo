//! Git working-tree status and diffs, mirroring fx-ui-main/src/host/git.rs.
//! Parsing is pure and tested; process calls are isolated in `runGit`.
const std = @import("std");

pub const LineKind = enum { context, added, removed, hunk };

pub const DiffLine = struct {
    kind: LineKind,
    old: ?usize = null,
    new: ?usize = null,
    body: []const u8,
};

pub const Change = struct {
    path: []const u8,
    code: u8,
    staged: bool,
    added: usize = 0,
    removed: usize = 0,
};

pub const Snapshot = struct {
    alloc: std.mem.Allocator,
    changes: std.ArrayList(Change) = .empty,
    branch: []u8 = undefined,
    last_commit: []u8 = undefined,
    err_msg: ?[]const u8 = null,

    pub fn init(alloc: std.mem.Allocator) Snapshot {
        return .{
            .alloc = alloc,
            .branch = alloc.dupe(u8, "HEAD") catch unreachable,
            .last_commit = alloc.dupe(u8, "") catch unreachable,
        };
    }

    pub fn deinit(s: *Snapshot) void {
        for (s.changes.items) |c| s.alloc.free(c.path);
        s.changes.deinit(s.alloc);
        s.alloc.free(s.branch);
        s.alloc.free(s.last_commit);
    }

    pub fn totals(s: *const Snapshot) struct { added: usize, removed: usize } {
        var a: usize = 0;
        var r: usize = 0;
        for (s.changes.items) |c| {
            a += c.added;
            r += c.removed;
        }
        return .{ .added = a, .removed = r };
    }
};

fn runGit(alloc: std.mem.Allocator, cwd: []const u8, argv: []const []const u8) ![]u8 {
    const io = @import("proc.zig").io();
    const result = try std.process.run(alloc, io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
    });
    defer alloc.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) {
        alloc.free(result.stdout);
        return error.GitFailed;
    }
    return result.stdout;
}

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

/// Parses `git status --porcelain=v1 -uall` into changes. Pure.
pub fn parseStatus(alloc: std.mem.Allocator, porcelain: []const u8) !std.ArrayList(Change) {
    var out: std.ArrayList(Change) = .empty;
    errdefer {
        for (out.items) |c| alloc.free(c.path);
        out.deinit(alloc);
    }
    var lines = std.mem.splitScalar(u8, porcelain, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len < 4) continue;
        const x = line[0];
        const y = line[1];
        var path = line[3..];
        if (std.mem.lastIndexOf(u8, path, " -> ")) |at| path = path[at + 4 ..];
        if (x == '?') {
            try out.append(alloc, .{ .path = try alloc.dupe(u8, path), .code = '?', .staged = false });
            continue;
        }
        if (x != ' ') {
            try out.append(alloc, .{ .path = try alloc.dupe(u8, path), .code = x, .staged = true });
        }
        if (y != ' ') {
            try out.append(alloc, .{ .path = try alloc.dupe(u8, path), .code = y, .staged = false });
        }
    }
    return out;
}

/// Parses a unified diff into rows. Pure.
pub fn parseUnified(alloc: std.mem.Allocator, text: []const u8) !std.ArrayList(DiffLine) {
    var out: std.ArrayList(DiffLine) = .empty;
    errdefer out.deinit(alloc);
    var old: usize = 0;
    var new: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (std.mem.startsWith(u8, line, "@@ ")) {
            var parts = std.mem.tokenizeAny(u8, line[3..], " \t");
            const os = parts.next() orelse "-0,0";
            const ns = parts.next() orelse "+0,0";
            old = parseHunkStart(os);
            new = parseHunkStart(ns);
            try out.append(alloc, .{ .kind = .hunk, .body = try alloc.dupe(u8, line) });
        } else if (out.items.len == 0) {
            continue;
        } else if (line.len > 0 and line[0] == '+') {
            try out.append(alloc, .{ .kind = .added, .new = new, .body = try alloc.dupe(u8, line[1..]) });
            new += 1;
        } else if (line.len > 0 and line[0] == '-') {
            try out.append(alloc, .{ .kind = .removed, .old = old, .body = try alloc.dupe(u8, line[1..]) });
            old += 1;
        } else if (line.len > 0 and line[0] == ' ') {
            try out.append(alloc, .{ .kind = .context, .old = old, .new = new, .body = try alloc.dupe(u8, line[1..]) });
            old += 1;
            new += 1;
        }
    }
    return out;
}

fn parseHunkStart(token: []const u8) usize {
    if (token.len < 2 or token[0] != '-' and token[0] != '+') return 1;
    const digits = token[1..];
    const comma = std.mem.indexOfScalar(u8, digits, ',') orelse digits.len;
    return std.fmt.parseInt(usize, digits[0..comma], 10) catch 1;
}

pub fn freeLines(alloc: std.mem.Allocator, lines: *std.ArrayList(DiffLine)) void {
    for (lines.items) |l| alloc.free(l.body);
    lines.deinit(alloc);
    // Reset to a valid empty list: a caller may render it before refilling,
    // and a stale len would walk freed memory.
    lines.* = .empty;
}

/// Refreshes status, branch and last commit from a workspace path.
pub fn refresh(s: *Snapshot, cwd: []const u8) void {
    const porcelain = runGit(s.alloc, cwd, &.{ "git", "status", "--porcelain=v1", "-uall" }) catch |err| {
        s.err_msg = @errorName(err);
        return;
    };
    defer s.alloc.free(porcelain);

    const parsed = parseStatus(s.alloc, porcelain) catch return;
    for (s.changes.items) |c| s.alloc.free(c.path);
    s.changes.deinit(s.alloc);
    s.changes = parsed;
    s.err_msg = null;

    // Counts from numstat, matched by path.
    applyNumstat(s.alloc, cwd, &s.changes, &.{ "git", "diff", "--cached", "--numstat", "-z" }, true);
    applyNumstat(s.alloc, cwd, &s.changes, &.{ "git", "diff", "--numstat", "-z" }, false);
    countUntrackedLines(s.alloc, cwd, &s.changes);

    if (runGit(s.alloc, cwd, &.{ "git", "rev-parse", "--abbrev-ref", "HEAD" })) |b| {
        defer s.alloc.free(b);
        // Free the old value only once, after a successful dupe. Freeing before
        // the dupe (and again after) is a double free that traps on click.
        if (s.alloc.dupe(u8, trim(b))) |dup| {
            s.alloc.free(s.branch);
            s.branch = dup;
        } else |_| {}
    } else |_| {}

    if (runGit(s.alloc, cwd, &.{ "git", "log", "-1", "--format=%h · %cr" })) |l| {
        defer s.alloc.free(l);
        if (s.alloc.dupe(u8, trim(l))) |dup| {
            s.alloc.free(s.last_commit);
            s.last_commit = dup;
        } else |_| {}
    } else |_| {}
}

fn isBinaryPath(path: []const u8) bool {
    const binary_exts = [_][]const u8{
        ".png",   ".jpg", ".jpeg", ".gif",    ".webp", ".ico", ".icns", ".bmp",  ".tiff",
        ".pdf",   ".zip", ".gz",   ".bz2",    ".xz",   ".7z",  ".tar",  ".woff", ".woff2",
        ".ttf",   ".otf", ".mp3",  ".mp4",    ".mov",  ".wav", ".a",    ".o",    ".so",
        ".dylib", ".exe", ".bin",  ".sqlite", ".db",
    };
    const ext = std.fs.path.extension(path);
    for (binary_exts) |b| {
        if (std.ascii.eqlIgnoreCase(ext, b)) return true;
    }
    return false;
}

/// Counts lines of untracked files (design's untracked_lines), bounded so a
/// huge generated file cannot stall the UI.
///
/// `git status` reports paths relative to the repository root even when run in
/// a subdirectory, and `std.Io.Dir.cwd()` does not resolve relative paths under
/// this Threaded Io, so both the root and each path are made absolute.
fn countUntrackedLines(alloc: std.mem.Allocator, cwd: []const u8, changes: *std.ArrayList(Change)) void {
    const io = @import("proc.zig").io();
    const root_raw = runGit(alloc, cwd, &.{ "git", "rev-parse", "--show-toplevel" }) catch return;
    defer alloc.free(root_raw);
    const root = trim(root_raw);
    if (root.len == 0) return;
    for (changes.items) |*ch| {
        if (ch.code != '?' or ch.added != 0) continue;
        // Binary files have no line count (the design skips them too).
        if (isBinaryPath(ch.path)) continue;
        const full = std.fmt.allocPrint(alloc, "{s}/{s}", .{ root, ch.path }) catch continue;
        defer alloc.free(full);
        var file = std.Io.Dir.cwd().openFile(io, full, .{}) catch continue;
        defer file.close(io);
        var buf: [65536]u8 = undefined;
        var reader = file.reader(io, &buf);
        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(alloc);
        reader.interface.appendRemaining(alloc, &content, .limited(2 * 1024 * 1024)) catch continue;
        var count: usize = 0;
        for (content.items) |byte| if (byte == '\n') {
            count += 1;
        };
        if (content.items.len > 0 and content.items[content.items.len - 1] != '\n') count += 1;
        ch.added = count;
    }
}

/// git add <path> (design's git::stage).
pub fn stage(cwd: []const u8, path: []const u8) bool {
    return runSimple(cwd, &.{ "git", "add", "--", path });
}

/// git reset HEAD -- <path> (design's git::unstage).
pub fn unstage(cwd: []const u8, path: []const u8) bool {
    return runSimple(cwd, &.{ "git", "reset", "HEAD", "--", path });
}

/// git checkout -- <path> (design's git::discard).
pub fn discard(cwd: []const u8, path: []const u8) bool {
    return runSimple(cwd, &.{ "git", "checkout", "--", path });
}

fn runSimple(cwd: []const u8, argv: []const []const u8) bool {
    const io = @import("proc.zig").io();
    const alloc = std.heap.c_allocator;
    const result = std.process.run(alloc, io, .{ .argv = argv, .cwd = .{ .path = cwd } }) catch return false;
    const ok = result.term == .exited and result.term.exited == 0;
    alloc.free(result.stdout);
    alloc.free(result.stderr);
    return ok;
}

fn applyNumstat(alloc: std.mem.Allocator, cwd: []const u8, changes: *std.ArrayList(Change), argv: []const []const u8, staged: bool) void {
    const text = runGit(alloc, cwd, argv) catch return;
    defer alloc.free(text);
    var fields = std.mem.splitScalar(u8, text, 0);
    while (fields.next()) |record| {
        if (record.len == 0) continue;
        var parts = std.mem.splitScalar(u8, record, '\t');
        const a_s = parts.next() orelse continue;
        const r_s = parts.next() orelse continue;
        const path = parts.next() orelse continue;
        const added = std.fmt.parseInt(usize, a_s, 10) catch 0;
        const removed = std.fmt.parseInt(usize, r_s, 10) catch 0;
        for (changes.items) |*c| {
            if (c.staged == staged and std.mem.eql(u8, c.path, path)) {
                c.added = added;
                c.removed = removed;
            }
        }
    }
}

test "parseStatus handles staged, unstaged and untracked" {
    const text =
        "M  src/main.zig\n" ++
        " M src/view.zig\n" ++
        "?? desktop/new.zig\n" ++
        "A  renamed -> desktop/renamed.zig\n";
    var list = try parseStatus(std.testing.allocator, text);
    defer {
        for (list.items) |c| std.testing.allocator.free(c.path);
        list.deinit(std.testing.allocator);
    }
    try std.testing.expectEqual(@as(usize, 4), list.items.len);
    try std.testing.expectEqualStrings("src/main.zig", list.items[0].path);
    try std.testing.expect(list.items[0].staged);
    try std.testing.expect(!list.items[1].staged);
    try std.testing.expectEqual(@as(u8, '?'), list.items[2].code);
    try std.testing.expectEqualStrings("desktop/renamed.zig", list.items[3].path);
}

test "parseUnified reads hunks and rows" {
    const text =
        "diff --git a/x b/x\n" ++
        "--- a/x\n" ++
        "+++ b/x\n" ++
        "@@ -1,3 +1,4 @@\n" ++
        " keep\n" ++
        "-old\n" ++
        "+new\n" ++
        "+extra\n";
    var lines = try parseUnified(std.testing.allocator, text);
    defer freeLines(std.testing.allocator, &lines);
    try std.testing.expectEqual(@as(usize, 5), lines.items.len);
    try std.testing.expectEqual(LineKind.hunk, lines.items[0].kind);
    try std.testing.expectEqual(LineKind.context, lines.items[1].kind);
    try std.testing.expectEqual(LineKind.removed, lines.items[2].kind);
    try std.testing.expectEqual(LineKind.added, lines.items[3].kind);
    try std.testing.expectEqual(@as(usize, 2), lines.items[3].new.?);
}
