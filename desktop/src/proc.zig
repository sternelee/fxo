//! A real Threaded Io for child processes. Zig's `global_single_threaded`
//! uses a failing allocator and cannot run `std.process.run`; nanoui's own Io
//! is private to its runtime. This one is ours, with a working allocator and
//! the process environment so `git` resolves on PATH.
const std = @import("std");

var threaded: std.Io.Threaded = undefined;
var ready: bool = false;

/// Called once from main with nanoui's Minimal init (args + environ).
pub fn initFrom(min: std.process.Init.Minimal) void {
    threaded = std.Io.Threaded.init(std.heap.c_allocator, .{
        .argv0 = .init(min.args),
        .environ = min.environ,
    });
    ready = true;
}

pub fn io() std.Io {
    if (!ready) {
        // Fallback for tests/probes: empty environ still resolves absolute
        // paths; c_allocator makes the internal allocations work.
        threaded = std.Io.Threaded.init(std.heap.c_allocator, .{});
        ready = true;
    }
    return threaded.io();
}
