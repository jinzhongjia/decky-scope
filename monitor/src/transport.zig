const std = @import("std");
const sys = @import("sys.zig");
const MAX = @import("protocol.zig").MAX_LINE;
pub const Transport = struct {
    input: [MAX]u8 = @splat(0),
    in_len: usize = 0,
    output: [MAX * 2]u8 = @splat(0),
    out_len: usize = 0,
    out_pos: usize = 0,
    pub fn queue(self: *Transport, bytes: []const u8) !void {
        if (bytes.len > MAX) return error.LineTooLong;
        if (self.out_pos > 0) {
            std.mem.copyForwards(u8, &self.output, self.output[self.out_pos..self.out_len]);
            self.out_len -= self.out_pos;
            self.out_pos = 0;
        }
        if (bytes.len > self.output.len - self.out_len) return error.Backpressure;
        @memcpy(self.output[self.out_len..][0..bytes.len], bytes);
        self.out_len += bytes.len;
    }
    pub fn flush(self: *Transport, fd: i32) !void {
        // One nonblocking syscall per event-loop turn; no client can monopolize ticks.
        if (self.out_pos == self.out_len) return;
        const n = sys.send(fd, self.output[self.out_pos..self.out_len]) catch |err| {
            if (err == error.Again) return;
            return err;
        };
        if (n == 0) return error.Closed;
        self.out_pos += n;
        if (self.out_pos == self.out_len) {
            self.out_pos = 0;
            self.out_len = 0;
        }
    }
    pub fn receive(self: *Transport, fd: i32) !void {
        if (self.in_len == self.input.len) return error.LineTooLong;
        const n = sys.recv(fd, self.input[self.in_len..]) catch |err| {
            if (err == error.Again) return;
            return err;
        };
        if (n == 0) return error.Closed;
        self.in_len += n;
    }
    pub fn line(self: *Transport) ?[]const u8 {
        const n = std.mem.indexOfScalar(u8, self.input[0..self.in_len], '\n') orelse return null;
        return self.input[0..n];
    }
    pub fn consume(self: *Transport, n: usize) void {
        std.mem.copyForwards(u8, &self.input, self.input[n..self.in_len]);
        self.in_len -= n;
    }
};
test "transport retains frame boundaries and rejects unbounded output" {
    const t = try std.testing.allocator.create(Transport);
    defer std.testing.allocator.destroy(t);
    t.* = .{};
    @memcpy(t.input[0..6], "one\nx\n");
    t.in_len = 6;
    try std.testing.expectEqualStrings("one", t.line().?);
    t.consume(4);
    try std.testing.expectEqualStrings("x", t.line().?);
    t.out_len = t.output.len;
    try std.testing.expectError(error.Backpressure, t.queue("x\n"));
}
