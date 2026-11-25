//! Thread: transcript with the working timeline, mirroring
//! fx-ui-main/src/views/thread/mod.rs and timeline.rs.
const std = @import("std");
const ui = @import("nanoui").ui;
const t = @import("tokens.zig");
const w = @import("widgets.zig");
const State = @import("state.zig").State;
const Step = @import("engine.zig").ToolStep;

fn stepIcon(c: *ui.Context, step: *const Step) void {
    // Mirrors fx-ui-main/src/views/thread/timeline.rs step_icon().
    const name: []const u8 = if (std.mem.eql(u8, step.nameSlice(), "subagent"))
        "user"
    else if (std.mem.eql(u8, step.nameSlice(), "ask_user_question"))
        "lines"
    else if (std.mem.eql(u8, step.kindSlice(), "read"))
        "file"
    else if (std.mem.eql(u8, step.kindSlice(), "edit"))
        "pencil"
    else if (std.mem.eql(u8, step.kindSlice(), "search"))
        "search"
    else if (std.mem.eql(u8, step.kindSlice(), "fetch"))
        "globe"
    else if (std.mem.eql(u8, step.kindSlice(), "delete"))
        "trash"
    else
        "terminal";
    @import("icons.zig").draw(c, name, 14, t.gray_900);
}

fn verb(step: *const Step) []const u8 {
    const k = step.kindSlice();
    if (std.mem.eql(u8, k, "execute")) return "Ran";
    if (std.mem.eql(u8, k, "edit")) return "Edited";
    if (std.mem.eql(u8, k, "read")) return "Read";
    if (std.mem.eql(u8, k, "search")) return "Searched";
    if (std.mem.eql(u8, k, "fetch")) return "Fetched";
    if (std.mem.eql(u8, k, "delete")) return "Deleted";
    return step.nameSlice();
}

fn stepRow(c: *ui.Context, step: *const Step, above: bool, below: bool, more: usize, grouped: bool, open: bool) void {
    const row = ui.div(c).row().wFull().h(30).gap(10).itemsCenter();
    defer row.end();

    // Gutter: a 16pt rail with a mark and connecting lines.
    {
        const gutter = ui.div(c).column().w(16).itemsCenter();
        defer gutter.end();
        const top = ui.div(c).w(1).h(8).bg(if (above) t.alpha_300 else t.background_100);
        top.end();
        if (step.isLive()) {
            // A live step spins, like the design's spinner(14).
            w.spinner(c, c.print("step-spin-{s}", .{step.idSlice()}), t.gray_1000);
        } else if (step.isFailed()) {
            w.dot(c, t.red_900);
        } else {
            stepIcon(c, step);
        }
        const bot = ui.div(c).w(1).grow().bg(if (below) t.alpha_300 else t.background_100);
        bot.end();
    }

    const tone: ui.Color = if (step.isFailed()) t.red_900 else if (step.isLive()) t.gray_1000 else t.gray_700;
    ui.text(c, verb(step), .{ .size = 13, .line_height = 18, .color = tone });
    ui.text(c, step.detailSlice(), .{ .size = 12, .line_height = 18, .mono = true, .family = t.mono_family, .truncate = .ellipsis, .color = if (step.isLive()) t.gray_1000 else t.gray_900 });
    if (more > 0) {
        ui.text(c, c.print("+{d} more", .{more}), .{ .size = 12, .line_height = 18, .color = t.gray_700 });
    }
    // A folded group carries a chevron showing whether it is open.
    if (grouped) {
        @import("icons.zig").draw(c, if (open) "chevron-down" else "chevron-right", 12, t.gray_700);
    }
}

fn thoughtRow(c: *ui.Context, thought: []const u8, below: bool) void {
    const row = ui.div(c).row().wFull().h(30).gap(10).itemsCenter();
    defer row.end();
    {
        const gutter = ui.div(c).column().w(16).itemsCenter();
        defer gutter.end();
        const top = ui.div(c).w(1).h(8).bg(t.background_100);
        top.end();
        @import("icons.zig").draw(c, "ellipsis", 14, t.gray_700);
        const bot = ui.div(c).w(1).grow().bg(if (below) t.alpha_300 else t.background_100);
        bot.end();
    }
    ui.text(c, "Thought", .{ .size = 13, .line_height = 18, .color = t.gray_700 });
    const first_line = if (std.mem.indexOfScalar(u8, thought, '\n')) |at| thought[0..at] else thought;
    ui.text(c, first_line, .{ .size = 13, .line_height = 18, .truncate = .ellipsis, .color = t.gray_700 });
}

fn outputRow(c: *ui.Context, output: []const u8) void {
    const box = ui.div(c).column().wFull().pl(26).pb(8);
    defer box.end();
    const card = ui.div(c).column().wFull().px(12).py(10).rounded(8).bg(t.background_200).border(t.alpha_200).borderW(1);
    defer card.end();
    var lines = std.mem.splitScalar(u8, output, '\n');
    var shown: usize = 0;
    while (lines.next()) |line| {
        if (shown >= 6) break;
        if (line.len == 0) continue;
        ui.text(c, line, .{ .size = 12, .line_height = 18, .mono = true, .family = t.mono_family, .truncate = .ellipsis, .color = t.gray_900 });
        shown += 1;
    }
}

fn questionCard(c: *ui.Context, s: *State, q: *const @import("acp_parse.zig").Question) void {
    const card = ui.div(c).column().wFull().pl(26).pb(8).gap(6);
    defer card.end();
    {
        const head = ui.div(c).row().wFull().gap(10).itemsStart();
        defer head.end();
        w.dot(c, t.amber_700);
        ui.text(c, q.promptSlice(), .{ .size = 14, .line_height = 22, .weight = .medium, .wrap = true, .color = t.gray_1000 });
    }
    for (0..q.option_count) |i| {
        ui.key(c, c.print("answer-{d}", .{i}));
        const row = ui.div(c).row().wFull().h(40).px(12).gap(10).itemsCenter().rounded(8)
            .border(t.alpha_300).borderW(1).control().hover(t.alpha_200);
        defer row.end();
        ui.text(c, c.print("{d}", .{i + 1}), .{ .size = 12, .mono = true, .family = t.mono_family, .color = t.gray_700 });
        ui.text(c, q.optionSlice(i), .{ .size = 13, .line_height = 18, .truncate = .ellipsis, .color = t.gray_1000 });
        // Picking an option puts it in the composer, ready to send.
        if (row.clicked()) s.input.set(q.optionSlice(i));
    }
    {
        // "Something else…" focuses the composer instead of answering.
        ui.key(c, "answer-other");
        const other = ui.div(c).row().wFull().h(40).px(12).gap(10).itemsCenter().rounded(8)
            .border(t.alpha_300).borderW(1).control().hover(t.alpha_200);
        defer other.end();
        ui.text(c, c.print("{d}", .{q.option_count + 1}), .{ .size = 12, .mono = true, .family = t.mono_family, .color = t.gray_700 });
        ui.text(c, "Something else…", .{ .size = 13, .line_height = 18, .color = t.gray_700 });
        if (other.clicked()) s.input.focus();
    }
    {
        const foot = ui.div(c).row().wFull().gap(8).itemsCenter();
        defer foot.end();
        ui.text(c, "Press a number, or type an answer below", w.faint(12, 16));
        {
            const spacer = ui.div(c).grow();
            defer spacer.end();
        }
        if (w.button(c, "question-skip", "Skip", false)) {
            s.status_line = "Question skipped";
        }
    }
}

pub fn view(s: *State, c: *ui.Context) void {
    // The transcript sits at the bottom of its viewport and grows upward, like
    // the design's bottom_aligned(): a full-height column justified to the end.
    const scroll = ui.div(c).column().grow().wFull().hFull().scrollY().justifyEnd().itemsCenter().px(40).pt(24).pb(24);
    defer scroll.end();
    const col = ui.div(c).column().wFull().maxW(t.column_width).gap(20);
    defer col.end();

    const session = s.currentSession();
    if (session == null or session.?.turns.items.len == 0) {
        ui.text(c, "Loading…", w.faint(13, 18));
        return;
    }
    for (session.?.turns.items, 0..) |turn, i| {
        ui.key(c, c.print("turn-{d}", .{i}));
        const group = ui.div(c).column().wFull().gap(20);
        defer group.end();

        {
            const prompt_row = ui.div(c).column().wFull().itemsEnd().gap(8);
            defer prompt_row.end();
            // Image thumbnails above the bubble (design's thumbnails()).
            if (turn.images.items.len > 0) {
                const strip = ui.div(c).row().gap(8);
                defer strip.end();
                for (turn.images.items, 0..) |bytes, ii| {
                    ui.key(c, c.print("turn-{d}-shot-{d}", .{ i, ii }));
                    const thumb = ui.div(c).size(96, 72).rounded(10).clip();
                    defer thumb.end();
                    _ = ui.image(c, .{ .key = c.print("turn-{d}-img-{d}", .{ i, ii }), .bytes = bytes, .box = .{ .w = 96, .h = 72 }, .radius = 10 });
                }
            }
            const bubble = ui.div(c).column().maxW(520).px(16).py(10).rounded(18).bg(t.gray_200);
            defer bubble.end();
            ui.text(c, turn.prompt, .{ .size = 14, .line_height = 22, .wrap = true, .color = t.gray_1000 });
        }

        // Work timeline: live turns show "Working" with the recent steps;
        // settled turns fold into a "Worked for Ns · N actions" summary the
        // user can expand (design's working()/worked()).
        const has_work = turn.step_count > 0 or turn.thought.items.len > 0;
        const live = turn.status == .running or turn.status == .waiting;
        if (has_work or live) {
            const secs = turn.elapsed_ms / 1000;
            const actions = c.print("{d} action{s}", .{ turn.step_count, if (turn.step_count == 1) "" else "s" });
            const open = s.isExpanded(i);

            if (live) {
                const working = ui.div(c).row().h(24).gap(8).itemsCenter();
                defer working.end();
                w.spinner(c, c.print("spin-{d}", .{i}), t.gray_1000);
                ui.text(c, "Working", w.textStyle(13, 18));
                ui.text(c, c.print("{d}s · {s}", .{ secs, actions }), w.faint(13, 18));
            } else {
                const head = ui.div(c).row().h(24).gap(6).itemsCenter().control();
                defer head.end();
                const tone = if (open) t.gray_1000 else t.gray_900;
                const label = if (secs > 0)
                    c.print("Worked for {d}s", .{secs})
                else
                    c.print("Worked · {s}", .{actions});
                ui.text(c, label, .{ .size = 13, .line_height = 18, .color = tone });
                @import("icons.zig").draw(c, if (open) "chevron-down" else "chevron-right", 12, tone);
                if (open and secs > 0) ui.text(c, c.print("· {s}", .{actions}), w.faint(13, 18));
                if (head.clicked()) s.toggleTurn(i);
            }

            // The step list: recent six while working, all when expanded.
            const show_steps = live or open;
            if (show_steps and has_work) {
                const timeline = ui.div(c).column().wFull().gap(2);
                defer timeline.end();
                if (turn.thought.items.len > 0) thoughtRow(c, turn.thought.items, turn.step_count > 0);
                var si: usize = 0;
                while (si < turn.step_count) {
                    const step = &turn.steps[si];
                    var more: usize = 0;
                    if (!step.isLive() and !step.isFailed() and step.question == null) {
                        while (si + more + 1 < turn.step_count) {
                            const next = &turn.steps[si + more + 1];
                            if (next.isLive() or next.isFailed() or next.question != null) break;
                            if (!std.mem.eql(u8, next.kindSlice(), step.kindSlice())) break;
                            more += 1;
                        }
                    }
                    stepRow(c, step, si > 0 or turn.thought.items.len > 0, si + more + 1 < turn.step_count, more, more > 0, open);
                    if (step.outputSlice().len > 0) outputRow(c, step.outputSlice());
                    if (step.question) |*q| questionCard(c, s, q);
                    si += more + 1;
                }
            }
        }

        if (turn.answer.items.len > 0) {
            const answer = ui.div(c).column().wFull().gap(14);
            defer answer.end();
            ui.markdown.view(c, turn.answer.items, .{
                .size = 14,
                .line_height = 22,
                .wrap = true,
                .color = t.gray_1000,
            }, .{ .code_background = .{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 0.16 } });
            {
                const footer = ui.div(c).row().h(28).gap(2).itemsCenter();
                defer footer.end();
                if (w.iconButton(c, c.print("copy-{d}", .{i}), "copy")) {
                    c.clipboard.write(c.clipboard.ctx, turn.answer.items);
                }
                // "model · duration", like the design's answer_footer.
                const model = @import("fxcli.zig").modelName(s.alloc, s.fx_info.model.slice());
                const secs = turn.elapsed_ms / 1000;
                const note = if (model.len > 0 and secs > 0)
                    c.print("{s} · {d}s", .{ model, secs })
                else if (model.len > 0)
                    model
                else if (secs > 0)
                    c.print("{d}s", .{secs})
                else
                    "";
                ui.text(c, note, w.faint(12, 16));
            }
        }

        // Files changed card on the last turn, mirroring timeline.rs files_card.
        if (i + 1 == session.?.turns.items.len and s.changes.changes.items.len > 0) {
            const files = &s.changes;
            const totals = files.totals();
            const card = ui.div(c).column().wFull().rounded(12).border(t.alpha_400).borderW(1).clip();
            defer card.end();
            {
                const head = ui.div(c).row().wFull().h(40).px(14).gap(8).itemsCenter().bg(t.gray_100);
                defer head.end();
                const label = c.print("{d} file{s} changed", .{ files.changes.items.len, if (files.changes.items.len == 1) "" else "s" });
                ui.text(c, label, .{ .size = 13, .line_height = 18, .weight = .medium, .color = t.gray_1000 });
                if (totals.added > 0) ui.text(c, c.print("+{d}", .{totals.added}), .{ .size = 12, .mono = true, .family = t.mono_family, .color = t.green_900 });
                if (totals.removed > 0) ui.text(c, c.print("−{d}", .{totals.removed}), .{ .size = 12, .mono = true, .family = t.mono_family, .color = t.red_900 });
                {
                    const spacer = ui.div(c).grow();
                    defer spacer.end();
                }
                // "Review ›" as a text link, like the design's files_card.
                ui.key(c, "review-changes");
                const review = ui.div(c).row().gap(8).itemsCenter().control().hover(t.alpha_100);
                defer review.end();
                ui.text(c, "Review", .{ .size = 13, .line_height = 18, .color = t.gray_900 });
                @import("icons.zig").draw(c, "chevron-right", 12, t.gray_900);
                if (review.clicked()) s.changes_open = true;
            }
            for (files.changes.items[0..@min(files.changes.items.len, 6)]) |ch| {
                const frow = ui.div(c).row().wFull().h(36).px(14).gap(10).itemsCenter();
                defer frow.end();
                ui.text(c, ch.path, .{ .size = 12, .mono = true, .family = t.mono_family, .truncate = .ellipsis, .color = t.gray_900 });
                {
                    const spacer = ui.div(c).grow();
                    defer spacer.end();
                }
                if (ch.added > 0) ui.text(c, c.print("+{d}", .{ch.added}), .{ .size = 12, .mono = true, .family = t.mono_family, .color = t.green_900 });
                if (ch.removed > 0) ui.text(c, c.print("−{d}", .{ch.removed}), .{ .size = 12, .mono = true, .family = t.mono_family, .color = t.red_900 });
            }
        }

        // Why the turn stopped, when fx reported something other than a
        // normal end (design's turn.stop).
        if (turn.stop_reason.len > 0 and !std.mem.eql(u8, turn.stop_reason, "end_turn")) {
            ui.text(c, stopReasonText(turn.stop_reason), .{ .size = 13, .line_height = 18, .color = t.gray_700 });
        }
    }
}

/// A human phrase for an ACP stopReason.
fn stopReasonText(reason: []const u8) []const u8 {
    if (std.mem.eql(u8, reason, "cancelled")) return "Stopped before it finished.";
    if (std.mem.eql(u8, reason, "max_tokens")) return "Stopped at the token limit.";
    if (std.mem.eql(u8, reason, "max_turn_requests")) return "Stopped at the request limit.";
    if (std.mem.eql(u8, reason, "refusal")) return "The model declined to continue.";
    return reason;
}
