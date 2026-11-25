//! Pure ACP data types and JSON parsing, split out of engine.zig to keep files
//! under nanoui's 600-line ceiling. No I/O, no threads.
const std = @import("std");

pub fn copyBounded(dest: []u8, src: []const u8) usize {
    const n = @min(dest.len, src.len);
    @memcpy(dest[0..n], src[0..n]);
    return n;
}

pub const PermOption = struct {
    id: [32]u8 = undefined,
    id_len: usize = 0,
    name: [64]u8 = undefined,
    name_len: usize = 0,
    kind: [32]u8 = undefined,
    kind_len: usize = 0,

    pub fn idSlice(o: *const PermOption) []const u8 {
        return o.id[0..o.id_len];
    }
    pub fn nameSlice(o: *const PermOption) []const u8 {
        return o.name[0..o.name_len];
    }
    pub fn kindSlice(o: *const PermOption) []const u8 {
        return o.kind[0..o.kind_len];
    }
};

pub const DiffRow = struct {
    kind: enum { context, added, removed } = .context,
    old_no: usize = 0,
    new_no: usize = 0,
    text: [160]u8 = undefined,
    text_len: usize = 0,

    pub fn textSlice(r: *const DiffRow) []const u8 {
        return r.text[0..r.text_len];
    }
};

pub const Permission = struct {
    request_id: i64 = 0,
    question: [128]u8 = undefined,
    question_len: usize = 0,
    detail: [512]u8 = undefined,
    detail_len: usize = 0,
    kind: [32]u8 = undefined,
    kind_len: usize = 0,
    /// Diff preview lines for edit approvals (bounded).
    diff: [16]DiffRow = undefined,
    diff_count: usize = 0,
    diff_added: usize = 0,
    diff_removed: usize = 0,
    options: [4]PermOption = undefined,
    option_count: usize = 0,

    pub fn questionSlice(p: *const Permission) []const u8 {
        return p.question[0..p.question_len];
    }
    pub fn detailSlice(p: *const Permission) []const u8 {
        return p.detail[0..p.detail_len];
    }
    pub fn kindSlice(p: *const Permission) []const u8 {
        return p.kind[0..p.kind_len];
    }
    pub fn isExecute(p: *const Permission) bool {
        return std.mem.eql(u8, p.kindSlice(), "execute");
    }
    pub fn setQuestion(p: *Permission, v: []const u8) void {
        p.question_len = copyBounded(&p.question, v);
    }
    pub fn setDetail(p: *Permission, v: []const u8) void {
        p.detail_len = copyBounded(&p.detail, v);
    }
    pub fn setKind(p: *Permission, v: []const u8) void {
        p.kind_len = copyBounded(&p.kind, v);
    }
    pub fn addOption(p: *Permission, id: []const u8, name: []const u8, kind: []const u8) void {
        if (p.option_count >= p.options.len) return;
        var o = &p.options[p.option_count];
        o.id_len = copyBounded(&o.id, id);
        o.name_len = copyBounded(&o.name, name);
        o.kind_len = copyBounded(&o.kind, kind);
        p.option_count += 1;
    }
    pub fn byKind(p: *const Permission, kind: []const u8) ?*const PermOption {
        for (p.options[0..p.option_count]) |*o| {
            if (std.mem.eql(u8, o.kindSlice(), kind)) return o;
        }
        return null;
    }
    pub fn defaultAllow(p: *const Permission) ?*const PermOption {
        if (p.byKind("allow_once")) |o| return o;
        for (p.options[0..p.option_count]) |*o| {
            if (std.mem.startsWith(u8, o.kindSlice(), "allow_")) return o;
        }
        return null;
    }
};

pub const ToolStep = struct {
    id: [48]u8 = undefined,
    id_len: usize = 0,
    kind: [24]u8 = undefined,
    kind_len: usize = 0,
    name: [48]u8 = undefined,
    name_len: usize = 0,
    title: [160]u8 = undefined,
    title_len: usize = 0,
    detail: [256]u8 = undefined,
    detail_len: usize = 0,
    status: [24]u8 = undefined,
    status_len: usize = 0,
    output: [768]u8 = undefined,
    output_len: usize = 0,
    question: ?Question = null,

    pub fn idSlice(s: *const ToolStep) []const u8 {
        return s.id[0..s.id_len];
    }
    pub fn kindSlice(s: *const ToolStep) []const u8 {
        return s.kind[0..s.kind_len];
    }
    pub fn nameSlice(s: *const ToolStep) []const u8 {
        return s.name[0..s.name_len];
    }
    pub fn titleSlice(s: *const ToolStep) []const u8 {
        return s.title[0..s.title_len];
    }
    pub fn detailSlice(s: *const ToolStep) []const u8 {
        return s.detail[0..s.detail_len];
    }
    pub fn statusSlice(s: *const ToolStep) []const u8 {
        return s.status[0..s.status_len];
    }
    pub fn outputSlice(s: *const ToolStep) []const u8 {
        return s.output[0..s.output_len];
    }
    pub fn setId(s: *ToolStep, v: []const u8) void {
        s.id_len = copyBounded(&s.id, v);
    }
    pub fn setKind(s: *ToolStep, v: []const u8) void {
        s.kind_len = copyBounded(&s.kind, v);
    }
    pub fn setName(s: *ToolStep, v: []const u8) void {
        s.name_len = copyBounded(&s.name, v);
    }
    pub fn setTitle(s: *ToolStep, v: []const u8) void {
        s.title_len = copyBounded(&s.title, v);
    }
    pub fn setDetail(s: *ToolStep, v: []const u8) void {
        s.detail_len = copyBounded(&s.detail, v);
    }
    pub fn setStatus(s: *ToolStep, v: []const u8) void {
        s.status_len = copyBounded(&s.status, v);
    }
    pub fn appendOutput(s: *ToolStep, v: []const u8) void {
        const room = s.output.len - s.output_len;
        s.output_len += copyBounded(s.output[s.output_len..], v[0..@min(room, v.len)]);
    }
    pub fn isLive(s: *const ToolStep) bool {
        const st = s.statusSlice();
        return std.mem.eql(u8, st, "pending") or std.mem.eql(u8, st, "in_progress");
    }
    pub fn isFailed(s: *const ToolStep) bool {
        return std.mem.eql(u8, s.statusSlice(), "failed");
    }
};

/// A question from an `ask_user_question` tool call, with bounded options.
pub const Question = struct {
    prompt: [256]u8 = undefined,
    prompt_len: usize = 0,
    options: [6][128]u8 = undefined,
    option_lens: [6]usize = @splat(0),
    option_count: usize = 0,

    pub fn promptSlice(q: *const Question) []const u8 {
        return q.prompt[0..q.prompt_len];
    }
    pub fn optionSlice(q: *const Question, i: usize) []const u8 {
        return q.options[i][0..q.option_lens[i]];
    }
};

/// Extracts a question from a tool call's rawInput, if it is one.
pub fn parseQuestion(call: std.json.ObjectMap) ?Question {
    const name = textIn(call, "name");
    if (!std.mem.eql(u8, name, "ask_user_question")) return null;
    const raw = call.get("rawInput") orelse return null;
    if (raw != .object) return null;
    const questions = raw.object.get("questions") orelse return null;
    if (questions != .array or questions.array.items.len == 0) return null;
    const first = questions.array.items[0];
    if (first != .object) return null;
    var q: Question = .{};
    q.prompt_len = copyBounded(&q.prompt, textIn(first.object, "question"));
    const opts = first.object.get("options") orelse return null;
    if (opts != .array) return null;
    for (opts.array.items) |item| {
        if (q.option_count >= q.options.len) break;
        const label = if (item == .object) textIn(item.object, "label") else if (item == .string) item.string else "";
        if (label.len == 0) continue;
        q.option_lens[q.option_count] = copyBounded(&q.options[q.option_count], label);
        q.option_count += 1;
    }
    return if (q.option_count > 0) q else null;
}

pub fn textIn(obj: std.json.ObjectMap, key: []const u8) []const u8 {
    if (obj.get(key)) |v| if (v == .string) return v.string;
    return "";
}

fn objField(obj: std.json.ObjectMap, key: []const u8) ?std.json.ObjectMap {
    if (obj.get(key)) |v| {
        if (v == .object) return v.object;
    }
    return null;
}

fn strField(obj: std.json.ObjectMap, key: []const u8) []const u8 {
    return textIn(obj, key);
}

test "buildDiff produces added and removed rows" {
    var p: Permission = .{};
    buildDiff(&p, "let rows = self.rows.clone();\nfor row in rows {", "let workspaces = self.workspaces.read(cx);\nfor row in workspaces {");
    try std.testing.expect(p.diff_count > 0);
    try std.testing.expect(p.diff_added > 0);
    try std.testing.expect(p.diff_removed > 0);
}

test "parseQuestion extracts a question and options" {
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"name":"ask_user_question","kind":"other","rawInput":{"questions":[{"question":"Which color?","options":[{"label":"Red"},{"label":"Blue"}]}]}}
    , .{});
    defer parsed.deinit();
    const q = parseQuestion(parsed.value.object).?;
    try std.testing.expectEqualStrings("Which color?", q.promptSlice());
    try std.testing.expectEqual(@as(usize, 2), q.option_count);
    try std.testing.expectEqualStrings("Red", q.optionSlice(0));
    try std.testing.expectEqualStrings("Blue", q.optionSlice(1));
}

pub fn applyToolCall(step: *ToolStep, update: std.json.ObjectMap) void {
    step.setId(textIn(update, "toolCallId"));
    step.setName(textIn(update, "name"));
    step.setTitle(textIn(update, "title"));
    step.setKind(textIn(update, "kind"));
    step.setStatus(textIn(update, "status"));
    if (update.get("rawInput")) |ri| {
        if (ri == .object) {
            const keys = [_][]const u8{ "command", "path", "file_path", "pattern", "query", "url" };
            for (keys) |k| {
                const v = textIn(ri.object, k);
                if (v.len > 0) {
                    step.setDetail(v);
                    break;
                }
            }
        }
    }
    if (step.detailSlice().len == 0) step.setDetail(step.titleSlice());
    step.question = parseQuestion(update);
}

pub fn applyToolUpdate(steps: []ToolStep, step_count: usize, update: std.json.ObjectMap) void {
    const id = textIn(update, "toolCallId");
    var target: ?*ToolStep = null;
    for (steps[0..step_count]) |*step| {
        if (std.mem.eql(u8, step.idSlice(), id)) {
            target = step;
            break;
        }
    }
    const step = target orelse return;
    const status = textIn(update, "status");
    if (status.len > 0) step.setStatus(status);
    if (update.get("content")) |cv| {
        if (cv == .array) {
            for (cv.array.items) |item| {
                if (item != .object) continue;
                const inner = item.object.get("content") orelse continue;
                if (inner != .object) continue;
                step.appendOutput(textIn(inner.object, "text"));
            }
        }
    }
}

/// Builds a bounded line diff from old/new text (LCS). Pure.
pub fn buildDiff(p: *Permission, old: []const u8, new: []const u8) void {
    var a: [24][]const u8 = undefined;
    var b: [24][]const u8 = undefined;
    var na: usize = 0;
    var nb: usize = 0;
    var ai = std.mem.splitScalar(u8, old, '\n');
    while (ai.next()) |line| {
        if (na >= a.len) break;
        a[na] = std.mem.trimEnd(u8, line, "\r");
        na += 1;
    }
    var bi = std.mem.splitScalar(u8, new, '\n');
    while (bi.next()) |line| {
        if (nb >= b.len) break;
        b[nb] = std.mem.trimEnd(u8, line, "\r");
        nb += 1;
    }
    // LCS table (bounded small).
    var lcs: [25][25]u16 = @splat(@splat(0));
    var i: usize = na;
    while (i > 0) {
        i -= 1;
        var j: usize = nb;
        while (j > 0) {
            j -= 1;
            lcs[i][j] = if (std.mem.eql(u8, a[i], b[j]))
                lcs[i + 1][j + 1] + 1
            else
                @max(lcs[i + 1][j], lcs[i][j + 1]);
        }
    }
    i = 0;
    var j: usize = 0;
    while ((i < na or j < nb) and p.diff_count < p.diff.len) {
        if (i < na and j < nb and std.mem.eql(u8, a[i], b[j])) {
            addRow(p, .context, i + 1, j + 1, a[i]);
            i += 1;
            j += 1;
        } else if (i < na and (j >= nb or lcs[i + 1][j] >= lcs[i][j + 1])) {
            addRow(p, .removed, i + 1, 0, a[i]);
            i += 1;
        } else {
            addRow(p, .added, 0, j + 1, b[j]);
            j += 1;
        }
    }
}

fn addRow(p: *Permission, kind: @TypeOf(@as(DiffRow, .{}).kind), old_no: usize, new_no: usize, text: []const u8) void {
    var row = &p.diff[p.diff_count];
    row.* = .{ .kind = kind, .old_no = old_no, .new_no = new_no };
    row.text_len = copyBounded(&row.text, text);
    p.diff_count += 1;
    if (kind == .added) p.diff_added += 1 else if (kind == .removed) p.diff_removed += 1;
}

pub fn parsePermission(obj: std.json.ObjectMap) Permission {
    var p: Permission = .{};
    if (obj.get("id")) |idv| {
        if (idv == .integer) p.request_id = idv.integer;
    }
    const params = objField(obj, "params") orelse return p;
    const call = objField(params, "toolCall") orelse return p;
    const kind = strField(call, "kind");
    p.setKind(kind);
    const first: u8 = if (kind.len > 0) kind[0] else 0;
    p.setQuestion(switch (first) {
        'e' => "Run this command?",
        'd' => "Make this change?",
        'f' => "Fetch this?",
        else => "Allow this?",
    });
    var detail: []const u8 = "";
    if (objField(call, "rawInput")) |input| {
        const keys = [_][]const u8{ "command", "path", "file_path", "pattern", "query", "url" };
        for (keys) |k| {
            const v = strField(input, k);
            if (v.len > 0) {
                detail = v;
                break;
            }
        }
        // Edit tool calls carry old/new text; build a diff preview.
        const old_text = strField(input, "old_string");
        const new_text = strField(input, "new_string");
        if (old_text.len > 0 or new_text.len > 0) {
            buildDiff(&p, old_text, new_text);
        } else {
            const content = strField(input, "content");
            if (content.len > 0) buildDiff(&p, "", content);
        }
    }
    if (detail.len == 0) detail = strField(call, "title");
    p.setDetail(detail);
    if (params.get("options")) |ov| {
        if (ov == .array) {
            for (ov.array.items) |item| {
                if (item != .object) continue;
                p.addOption(strField(item.object, "optionId"), strField(item.object, "name"), strField(item.object, "kind"));
            }
        }
    }
    return p;
}
