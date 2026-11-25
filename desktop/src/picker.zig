//! Composer @/ / picker: trigger detection, file/skill discovery and ranking.
//! Mirrors fx-ui-main/src/app/draft.rs and host/pickers.rs. Pure logic + tests.
const std = @import("std");

pub const Kind = enum { file, skill };

pub const Item = struct {
    label: [96]u8 = undefined,
    label_len: usize = 0,
    detail: [160]u8 = undefined,
    detail_len: usize = 0,
    insert: [192]u8 = undefined,
    insert_len: usize = 0,

    pub fn labelSlice(i: *const Item) []const u8 {
        return i.label[0..i.label_len];
    }
    pub fn detailSlice(i: *const Item) []const u8 {
        return i.detail[0..i.detail_len];
    }
    pub fn insertSlice(i: *const Item) []const u8 {
        return i.insert[0..i.insert_len];
    }
    pub fn setLabel(i: *Item, v: []const u8) void {
        i.label_len = copy(&i.label, v);
    }
    pub fn setDetail(i: *Item, v: []const u8) void {
        i.detail_len = copy(&i.detail, v);
    }
    pub fn setInsert(i: *Item, v: []const u8) void {
        i.insert_len = copy(&i.insert, v);
    }
};

pub const Picker = struct {
    kind: Kind = .file,
    query: [96]u8 = undefined,
    query_len: usize = 0,
    items: [8]Item = undefined,
    count: usize = 0,
    selected: usize = 0,

    pub fn querySlice(p: *const Picker) []const u8 {
        return p.query[0..p.query_len];
    }
};

fn copy(dest: []u8, src: []const u8) usize {
    const n = @min(dest.len, src.len);
    @memcpy(dest[0..n], src[0..n]);
    return n;
}

/// Detects a trailing `@query` or `/query` token at the end of the draft.
/// Returns null when there is no active trigger.
pub fn trigger(draft: []const u8) ?struct { kind: Kind, query: []const u8 } {
    // Only the last whitespace-delimited token can trigger a picker.
    const last_space = std.mem.lastIndexOfAny(u8, draft, " \t\n") orelse 0;
    const start = if (last_space == 0 and (draft.len == 0 or draft[0] != '@' and draft[0] != '/')) 0 else if (last_space == 0) 0 else last_space + 1;
    const token = draft[start..];
    if (token.len == 0) return null;
    if (token[0] != '@' and token[0] != '/') return null;
    // A trigger with a space already typed after it is no longer active.
    if (std.mem.indexOfAny(u8, token, " \t\n") != null) return null;
    return .{
        .kind = if (token[0] == '@') .file else .skill,
        .query = token[1..],
    };
}

/// Subsequence score: contiguous matches and prefix matches rank higher.
fn score(text: []const u8, query: []const u8) ?i32 {
    if (query.len == 0) return 0;
    var best: ?i32 = null;
    var start: usize = 0;
    while (start < text.len) : (start += 1) {
        if (std.ascii.toLower(text[start]) != std.ascii.toLower(query[0])) continue;
        var s: i32 = 0;
        var at = start;
        var prev: ?usize = null;
        var ok = true;
        for (query) |q| {
            while (at < text.len and std.ascii.toLower(text[at]) != std.ascii.toLower(q)) : (at += 1) {}
            if (at >= text.len) {
                ok = false;
                break;
            }
            s += 1;
            if (prev != null and at == prev.? + 1) s += 2; // contiguous bonus
            if (at == 0) s += 3; // prefix bonus
            prev = at;
            at += 1;
        }
        if (ok and (best == null or s > best.?)) best = s;
    }
    return best;
}

/// Builds a picker from candidate paths or skills, ranked against the query.
pub fn build(p: *Picker, kind: Kind, query: []const u8, candidates: []const []const u8) void {
    p.* = .{ .kind = kind };
    p.query_len = copy(&p.query, query);

    const Scored = struct { text: []const u8, s: i32, len: usize };
    var scored: [64]Scored = undefined;
    var n: usize = 0;
    for (candidates) |cand| {
        if (n >= scored.len) break;
        const s = score(cand, query) orelse continue;
        scored[n] = .{ .text = cand, .s = s, .len = cand.len };
        n += 1;
    }
    // Simple insertion sort by score desc, then shorter text first.
    var i: usize = 1;
    while (i < n) : (i += 1) {
        const key = scored[i];
        var j = i;
        while (j > 0 and (scored[j - 1].s < key.s or (scored[j - 1].s == key.s and scored[j - 1].len > key.len))) : (j -= 1) {
            scored[j] = scored[j - 1];
        }
        scored[j] = key;
    }

    for (scored[0..@min(n, p.items.len)], 0..) |cand, idx| {
        var item = &p.items[idx];
        const path = cand.text;
        const base = std.fs.path.basename(path);
        if (kind == .file) {
            const dir = if (path.len > base.len) path[0 .. path.len - base.len - 1] else "";
            item.setLabel(base);
            item.setDetail(dir);
            var ins: [192]u8 = undefined;
            const ins_len = std.fmt.bufPrint(&ins, "@{s} ", .{path}) catch "";
            item.setInsert(ins_len);
        } else {
            item.setLabel(base);
            item.setDetail("skill");
            var ins: [192]u8 = undefined;
            const ins_len = std.fmt.bufPrint(&ins, "/{s} ", .{base}) catch "";
            item.setInsert(ins_len);
        }
        p.count += 1;
    }
}

test "trigger detects trailing @ and / tokens" {
    const a = trigger("fix the @src/ma").?;
    try std.testing.expect(a.kind == .file);
    try std.testing.expectEqualStrings("src/ma", a.query);
    const b = trigger("use /ski").?;
    try std.testing.expect(b.kind == .skill);
    try std.testing.expectEqualStrings("ski", b.query);
    try std.testing.expect(trigger("no trigger here") == null);
    try std.testing.expect(trigger("email a@b.com done") == null);
}

test "build ranks file candidates" {
    const paths = [_][]const u8{ "src/main.zig", "src/view.zig", "README.md" };
    var p: Picker = .{};
    build(&p, .file, "ma", &paths);
    try std.testing.expect(p.count >= 1);
    try std.testing.expectEqualStrings("main.zig", p.items[0].labelSlice());
    try std.testing.expectEqualStrings("@src/main.zig ", p.items[0].insertSlice());
}
