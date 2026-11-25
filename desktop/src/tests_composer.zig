//! Composer tests: the pill menus, the attach menu, the thinking pill and
//! prompt queueing. Headless, no window, no fx process.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const view = @import("view.zig");
const fixture = @import("tests.zig").fixture;

test "composer menu follows its pill anchor" {
    const CM = @import("composer_menu.zig");
    // A pill near the left: popup centers on it, above it.
    const left = CM.popupOrigin(.{ .x = 200, .y = 700 }, 300, 190, 1120, 760);
    try std.testing.expectEqual(@as(f32, 50), left.x); // 200 - 150
    try std.testing.expectEqual(@as(f32, 502), left.y); // 700 - 8 - 190
    // A pill near the right: popup shifts right with it.
    const right = CM.popupOrigin(.{ .x = 800, .y = 700 }, 300, 190, 1120, 760);
    try std.testing.expectEqual(@as(f32, 650), right.x); // 800 - 150
    try std.testing.expect(right.x > left.x);
    // Clamped inside the window when the pill is at an edge.
    const edge = CM.popupOrigin(.{ .x = 20, .y = 30 }, 300, 190, 1120, 760);
    try std.testing.expect(edge.x >= 8);
    try std.testing.expect(edge.y >= 8);
}
test "question card lists options and fills the composer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    const session = s.currentSession().?;
    const turn = &session.turns.items[0];
    var step = @import("engine.zig").ToolStep{};
    step.setId("q1");
    step.setKind("other");
    step.setName("ask_user_question");
    step.setStatus("completed");
    step.setDetail("Which color should the badge use?");
    const P = @import("acp_parse.zig");
    var q = P.Question{};
    q.prompt_len = P.copyBounded(&q.prompt, "Which color should the badge use?");
    q.option_lens[0] = P.copyBounded(&q.options[0], "Red");
    q.option_lens[1] = P.copyBounded(&q.options[1], "Blue");
    q.option_count = 2;
    step.question = q;
    turn.steps[0] = step;
    turn.step_count = 1;
    turn.status = .idle;
    s.toggleTurn(0);
    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Red"));
    try std.testing.expect(t.hasText("Blue"));
    try std.testing.expect(t.hasText("Something else…"));
    try std.testing.expect(t.hasText("Skip"));
    // Clicking an option puts it in the composer, ready to send.
    try t.clickText("Blue");
    t.settle(0.1);
    try std.testing.expectEqualStrings("Blue", s.input.text());
}
test "the attach menu offers file, images and paste" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .session;
    s.attach_menu = true;
    s.menu_anchor = .{ .x = 400, .y = 690 };

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("Mention a file"));
    try std.testing.expect(t.hasText("Choose images…"));
    try std.testing.expect(t.hasText("Paste image"));

    // Choosing "Mention a file" seeds the composer with @ and closes the menu.
    try t.clickText("Mention a file");
    t.settle(0.1);
    try std.testing.expect(!s.attach_menu);
    try std.testing.expectEqualStrings("@", s.input.text());
}
test "the thinking pill shows the level and opens its menu" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .session;
    // fx reports the effort; the pill labels it.
    s.fx_info.effort.set("high");

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    try std.testing.expect(t.hasText("High"));
    try std.testing.expect(s.composer_menu == null);

    // Clicking it opens the thinking menu.
    try t.clickText("High");
    t.settle(0.1);
    try std.testing.expect(s.composer_menu == .thinking);
}
test "a drafted prompt sends while a turn is running" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .session;
    const session = s.currentSession().?;
    session.status = .running;
    session.turns.items[0].status = .running;

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);

    // With nothing drafted the button stops the turn; a drafted prompt sends
    // (and queues) instead.
    s.input.set("queue this");
    t.settle(0.1);
    try std.testing.expectEqualStrings("queue this", s.input.text());
    s.sendPrompt();
    try std.testing.expectEqual(@as(usize, 1), session.queue.items.len);
    try std.testing.expectEqualStrings("queue this", session.queue.items[0]);
}

test "the usage menu meters spend, requests and tokens" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .session;
    s.fx_info.loaded = true;
    s.fx_info.usage_source.set("ai_gateway");
    s.fx_info.usage_status.set("ok");
    s.fx_info.spend = 2.5;
    s.fx_info.request_count = 12;
    s.fx_info.total_tokens = 4096;
    s.usage_period = "7d";
    s.composer_menu = .usage;
    s.menu_anchor = .{ .x = 700, .y = 690 };

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    // The three meters read fx's numbers, and each carries the period note.
    try std.testing.expect(t.hasText("Spend"));
    try std.testing.expect(t.hasText("$2.50"));
    try std.testing.expect(t.hasText("Requests"));
    try std.testing.expect(t.hasText("12"));
    try std.testing.expect(t.hasText("Tokens"));
    try std.testing.expect(t.hasText("4096"));
    try std.testing.expect(t.hasText("in the last 7 days"));
}

test "the model menu groups models by account" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .session;
    s.fx_info.loaded = true;
    s.fx_info.model.set("auto/glm-5.3");
    s.fx_info.catalog[0].set("auto/glm-5.3");
    s.fx_info.catalog[1].set("auto/deepseek-v4.1-flash-1017");
    s.fx_info.catalog[2].set("codex/gpt-6.2-sol");
    s.fx_info.catalog_count = 3;
    s.composer_menu = .model;
    s.menu_anchor = .{ .x = 760, .y = 690 };

    var t: ui.Tester = undefined;
    try t.init(alloc, .init(&s, view.view), .{ .width = 1120, .height = 760, .dark = true });
    defer t.deinit();
    t.settle(0.2);
    // Each account gets its own heading, taken from the id's prefix.
    try std.testing.expect(t.hasText("auto"));
    try std.testing.expect(t.hasText("codex"));
    try std.testing.expect(t.hasText("GLM 5.3"));
    try std.testing.expect(t.hasText("GPT 6.2 Sol"));
    try std.testing.expect(t.hasText("3 models"));
}

test "sending a prompt hands the engine the typed text, not an empty one" {
    // The composer's buffer is cleared as part of sending; a slice into it
    // would be empty by the time the engine reads it.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var s = fixture(alloc);
    s.page = .session;

    var engine = @import("engine.zig").Engine.init(alloc, "/tmp", struct {
        fn wake() void {}
    }.wake);
    defer engine.deinit();
    s.engine = &engine;

    s.input.set("hello world");
    s.sendPrompt();

    // The composer is empty, and the engine queued the real text.
    try std.testing.expectEqualStrings("", s.input.text());
    try std.testing.expectEqual(@as(usize, 1), engine.queue.items.len);
    try std.testing.expectEqualStrings("hello world", engine.queue.items[0]);
}
