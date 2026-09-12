const std = @import("std");
const sys = @import("sys.zig");
pub const capacity = 128;
pub const Event = struct { kind: enum(u8) { suspend_resume = 1, clock_change = 2 }, from_ms: u64, to_ms: u64 };
const size = 32;
const week = 7 * 86400000;
pub fn encode(e: Event) [size]u8 {
    var b: [size]u8 = @splat(0);
    @memcpy(b[0..4], "DSE1");
    b[4] = @intFromEnum(e.kind);
    std.mem.writeInt(u64, b[8..16], e.from_ms, .little);
    std.mem.writeInt(u64, b[16..24], e.to_ms, .little);
    std.mem.writeInt(u32, b[28..32], std.hash.Crc32.hash(b[0..28]), .little);
    return b;
}
pub fn decode(b: *const [size]u8) ?Event {
    if (!std.mem.eql(u8, b[0..4], "DSE1") or b[4] < 1 or b[4] > 2 or std.mem.readInt(u32, b[28..32], .little) != std.hash.Crc32.hash(b[0..28])) return null;
    return .{ .kind = @enumFromInt(b[4]), .from_ms = std.mem.readInt(u64, b[8..16], .little), .to_ms = std.mem.readInt(u64, b[16..24], .little) };
}
pub const Log = struct {
    items: [capacity]Event = undefined,
    len: usize = 0,
    failed: bool = false,
    truncated: bool = false,
    pub fn add(self: *Log, e: Event) void {
        if (self.len == capacity) {
            std.mem.copyForwards(Event, self.items[0 .. capacity - 1], self.items[1..]);
            self.len -= 1;
            self.truncated = true;
        }
        self.items[self.len] = e;
        self.len += 1;
    }
    pub fn prune(self: *Log, now: u64) bool {
        const before = self.len;
        var kept: usize = 0;
        for (self.items[0..self.len]) |e| {
            if (e.to_ms < now -| week) continue;
            self.items[kept] = e;
            kept += 1;
        }
        self.len = kept;
        return before != kept;
    }
    pub fn restore(self: *Log, directory: []const u8, now: u64) void {
        var p: [1024]u8 = undefined;
        const path = std.fmt.bufPrintZ(&p, "{s}/events.v1", .{directory}) catch return;
        const fd = sys.open(path) catch return;
        defer sys.close(fd);
        for (0..capacity) |i| {
            var b: [size]u8 = undefined;
            const n = sys.pread(fd, &b, @intCast(i * size)) catch {
                self.failed = true;
                return;
            };
            if (n == 0) break;
            if (n != size) {
                self.failed = true;
                return;
            }
            const e = decode(&b) orelse {
                self.failed = true;
                return;
            };
            const stamp = @max(e.from_ms, e.to_ms);
            if (stamp <= now and stamp >= now -| week) self.add(e);
        }
    }
    pub fn save(self: *Log, directory: []const u8) void {
        if (self.failed) return; // Preserve unreadable/unknown files for inspection.
        self.saveFile(directory) catch {
            self.failed = true;
        };
    }
    fn saveFile(self: *Log, directory: []const u8) !void {
        var p: [1024]u8 = undefined;
        var q: [1024]u8 = undefined;
        const temporary = try std.fmt.bufPrintZ(&p, "{s}/events.v1.tmp", .{directory});
        const destination = try std.fmt.bufPrintZ(&q, "{s}/events.v1", .{directory});
        const fd = try sys.openWrite(temporary);
        defer sys.close(fd);
        try sys.truncate(fd, 0);
        for (self.items[0..self.len], 0..) |e, i| try sys.pwriteAll(fd, &encode(e), i * size);
        try sys.sync(fd);
        const linux = std.os.linux;
        const rc = linux.syscall2(.rename, @intFromPtr(temporary.ptr), @intFromPtr(destination.ptr));
        if (linux.errno(rc) != .SUCCESS) return error.EventRenameFailed;
        var dirbuf: [1024]u8 = undefined;
        const dirpath = try std.fmt.bufPrintZ(&dirbuf, "{s}", .{directory});
        const dirfd = try sys.open(dirpath);
        defer sys.close(dirfd);
        if (linux.errno(linux.fsync(dirfd)) != .SUCCESS) return error.EventDirectorySyncFailed;
    }
};
test "event records roundtrip and reject corrupted kinds and checksums" {
    const e = Event{ .kind = .suspend_resume, .from_ms = 1000, .to_ms = 12000 };
    var b = encode(e);
    try std.testing.expectEqual(e, decode(&b).?);
    b[12] ^= 1;
    try std.testing.expect(decode(&b) == null);
}
test "event memory is bounded and preserves most recent entries" {
    var log: Log = .{};
    for (0..200) |i| log.add(.{ .kind = .clock_change, .from_ms = i, .to_ms = i + 1 });
    try std.testing.expectEqual(@as(usize, capacity), log.len);
    try std.testing.expectEqual(@as(u64, 72), log.items[0].from_ms);
    try std.testing.expect(log.truncated);
}
