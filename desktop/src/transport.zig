//! An in-memory transport for fx's ACP server, so the desktop app runs fx in
//! its own process the way the CLI does instead of spawning `fx acp`.
//!
//! Two byte queues: one the host writes requests into and the server reads,
//! one the server writes replies into and the host reads. Both are bounded and
//! thread-safe; `close()` wakes a blocked reader so the server can exit.
const std = @import("std");

const Spin = struct {
    flag: std.atomic.Value(bool) = .init(false),
    fn lock(self: *Spin) void {
        while (self.flag.swap(true, .acquire)) std.Thread.yield() catch {};
    }
    fn unlock(self: *Spin) void {
        self.flag.store(false, .release);
    }
};

/// A bounded byte queue with a reader that blocks until bytes or close.
pub const Pipe = struct {
    alloc: std.mem.Allocator,
    mutex: Spin = .{},
    buf: std.ArrayList(u8) = .empty,
    /// Bytes already handed to the reader, dropped on the next compact.
    consumed: usize = 0,
    closed: std.atomic.Value(bool) = .init(false),
    limit: usize,

    pub fn init(alloc: std.mem.Allocator, limit: usize) Pipe {
        return .{ .alloc = alloc, .limit = limit };
    }

    pub fn deinit(p: *Pipe) void {
        p.buf.deinit(p.alloc);
    }

    /// Appends bytes. Returns false when the pipe is closed or full.
    pub fn write(p: *Pipe, bytes: []const u8) bool {
        p.mutex.lock();
        defer p.mutex.unlock();
        if (p.closed.load(.acquire)) return false;
        if (p.buf.items.len - p.consumed + bytes.len > p.limit) return false;
        p.buf.appendSlice(p.alloc, bytes) catch return false;
        return true;
    }

    /// Copies up to `dest.len` bytes, waiting for some to arrive. Returns 0
    /// once the pipe is closed and drained.
    pub fn read(p: *Pipe, dest: []u8) usize {
        while (true) {
            p.mutex.lock();
            const available = p.buf.items.len - p.consumed;
            if (available > 0) {
                const n = @min(available, dest.len);
                @memcpy(dest[0..n], p.buf.items[p.consumed..][0..n]);
                p.consumed += n;
                // Compact once most of the buffer is spent, so it cannot grow
                // without bound over a long session.
                if (p.consumed > 64 * 1024 and p.consumed * 2 > p.buf.items.len) {
                    const rest = p.buf.items.len - p.consumed;
                    std.mem.copyForwards(u8, p.buf.items[0..rest], p.buf.items[p.consumed..]);
                    p.buf.shrinkRetainingCapacity(rest);
                    p.consumed = 0;
                }
                p.mutex.unlock();
                return n;
            }
            const done = p.closed.load(.acquire);
            p.mutex.unlock();
            if (done) return 0;
            std.Thread.yield() catch {};
        }
    }

    /// Non-blocking read: returns 0 immediately when nothing is available.
    /// Used by tests and by shutdown paths that cannot wait forever.
    pub fn tryRead(p: *Pipe, dest: []u8) usize {
        p.mutex.lock();
        defer p.mutex.unlock();
        const available = p.buf.items.len - p.consumed;
        if (available == 0) return 0;
        const n = @min(available, dest.len);
        @memcpy(dest[0..n], p.buf.items[p.consumed..][0..n]);
        p.consumed += n;
        if (p.consumed > 64 * 1024 and p.consumed * 2 > p.buf.items.len) {
            const rest = p.buf.items.len - p.consumed;
            std.mem.copyForwards(u8, p.buf.items[0..rest], p.buf.items[p.consumed..]);
            p.buf.shrinkRetainingCapacity(rest);
            p.consumed = 0;
        }
        return n;
    }

    /// Wakes a blocked reader and makes further writes fail.
    pub fn close(p: *Pipe) void {
        p.closed.store(true, .release);
    }
};

/// The pair of pipes an embedded fx server talks over.
pub const Transport = struct {
    /// Host → server (requests).
    to_server: Pipe,
    /// Server → host (replies and notifications).
    to_host: Pipe,

    pub fn init(alloc: std.mem.Allocator) Transport {
        return .{
            .to_server = Pipe.init(alloc, 8 * 1024 * 1024),
            .to_host = Pipe.init(alloc, 8 * 1024 * 1024),
        };
    }

    pub fn deinit(t: *Transport) void {
        t.to_server.deinit();
        t.to_host.deinit();
    }

    pub fn close(t: *Transport) void {
        t.to_server.close();
        t.to_host.close();
    }

    /// The reader the ACP server pulls requests from.
    pub fn reader(t: *Transport) @import("fx").jsonrpc.Reader {
        return @import("fx").jsonrpc.Reader.initCallback(t, readFromHost);
    }

    /// The writer the ACP server pushes replies to.
    pub fn writer(t: *Transport) @import("fx").jsonrpc.Writer {
        return @import("fx").jsonrpc.Writer.initCallback(t, writeToHost);
    }

    fn readFromHost(context: ?*anyopaque, dest: []u8) usize {
        const self: *Transport = @ptrCast(@alignCast(context.?));
        return self.to_server.read(dest);
    }

    fn writeToHost(context: ?*anyopaque, bytes: []const u8) anyerror!void {
        const self: *Transport = @ptrCast(@alignCast(context.?));
        if (!self.to_host.write(bytes)) return error.OutputClosed;
    }
};

test "a pipe hands bytes to its reader and closes cleanly" {
    var p = Pipe.init(std.testing.allocator, 1024);
    defer p.deinit();
    try std.testing.expect(p.write("hello\n"));
    var buf: [16]u8 = undefined;
    const n = p.read(&buf);
    try std.testing.expectEqualStrings("hello\n", buf[0..n]);
    p.close();
    try std.testing.expectEqual(@as(usize, 0), p.read(&buf));
    try std.testing.expect(!p.write("more"));
}

test "a pipe rejects writes past its limit" {
    var p = Pipe.init(std.testing.allocator, 4);
    defer p.deinit();
    try std.testing.expect(p.write("abcd"));
    try std.testing.expect(!p.write("e"));
}
