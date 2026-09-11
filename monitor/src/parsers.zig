const std = @import("std");
const model = @import("model.zig");
const source = @import("source.zig");
pub const Cpu = struct { total: u64, idle: u64 };
pub fn cpu(line: []const u8) ?Cpu {
    var it = std.mem.tokenizeAny(u8, line, " \t");
    _ = it.next() orelse return null;
    var out = Cpu{ .total = 0, .idle = 0 };
    var n: usize = 0;
    while (it.next()) |word| : (n += 1) {
        // guest and guest_nice are already included in user/nice.
        if (n >= 8) break;
        const v = std.fmt.parseInt(u64, word, 10) catch return null;
        out.total = std.math.add(u64, out.total, v) catch return null;
        if (n == 3 or n == 4) out.idle = std.math.add(u64, out.idle, v) catch return null;
    }
    return if (n >= 4) out else null;
}
pub fn usage(prev: ?Cpu, cur: Cpu) ?u16 {
    const p = prev orelse return null;
    if (cur.total <= p.total or cur.idle < p.idle) return null;
    const dt = cur.total - p.total;
    const di = @min(cur.idle - p.idle, dt);
    return @intCast(@as(u128, dt - di) * 1000 / dt);
}
pub fn meminfo(text: []const u8, s: *model.Sample) void {
    var total: ?i64 = null;
    var avail: ?i64 = null;
    var swap: ?i64 = null;
    var free: ?i64 = null;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        var it = std.mem.tokenizeAny(u8, line, " \t");
        const key = it.next() orelse continue;
        const v = source.integer(it.next() orelse continue) orelse continue;
        if (v < 0) continue;
        if (std.mem.eql(u8, key, "MemTotal:")) total = v;
        if (std.mem.eql(u8, key, "MemAvailable:")) avail = v;
        if (std.mem.eql(u8, key, "SwapTotal:")) swap = v;
        if (std.mem.eql(u8, key, "SwapFree:")) free = v;
    }
    if (total) |t| {
        s.set(.mem_total_mb, @divTrunc(t, 1024));
        if (avail) |a| if (a <= t) {
            s.set(.mem_used_mb, @divTrunc(t - a, 1024));
        };
    }
    if (swap) |t| if (free) |f| if (f <= t) {
        s.set(.swap_used_mb, @divTrunc(t - f, 1024));
    };
}
pub fn pressureTotal(text: []const u8, kind: []const u8) ?u64 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        var words = std.mem.tokenizeAny(u8, line, " \t");
        if (!std.mem.eql(u8, words.next() orelse continue, kind)) continue;
        while (words.next()) |word| if (std.mem.startsWith(u8, word, "total=")) {
            return std.fmt.parseInt(u64, word[6..], 10) catch null;
        };
    }
    return null;
}
pub fn rate(prev: ?u64, cur: ?u64, elapsed_us: u64, scale: u32, limit: u32) ?i64 {
    const a = prev orelse return null;
    const b = cur orelse return null;
    if (b < a or elapsed_us == 0) return null;
    return @intCast(@min(@as(u128, b - a) * scale / elapsed_us, limit));
}
test "CPU excludes duplicate guest time and handles reset" {
    const c = cpu("cpu 100 0 100 800 0 0 0 0 50 20").?;
    try std.testing.expectEqual(@as(u64, 1000), c.total);
    try std.testing.expectEqual(@as(?u16, 200), usage(.{ .total = 0, .idle = 0 }, c));
    try std.testing.expect(usage(c, .{ .total = 10, .idle = 1 }) == null);
    try std.testing.expect(usage(null, c) == null);
}
test "memory missing available does not mean full" {
    var s = model.Sample{};
    meminfo("MemTotal: 2048 kB\n", &s);
    try std.testing.expectEqual(@as(?i32, 2), s.get(.mem_total_mb));
    try std.testing.expect(s.get(.mem_used_mb) == null);
}
test "PSI fixed point and reset" {
    try std.testing.expectEqual(@as(?u64, 120), pressureTotal("some avg10=0.00 total=120\nfull total=4", "some"));
    try std.testing.expectEqual(@as(?i64, 2500), rate(0, 250000, 1000000, 10000, 10000));
    try std.testing.expect(rate(50, 1, 1000, 10000, 10000) == null);
}
