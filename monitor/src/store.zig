const std = @import("std");
const M = @import("model.zig");
pub fn Ring(comptime T: type, comptime N: usize) type {
    return struct {
        items: [N]T = std.mem.zeroes([N]T),
        head: usize = 0,
        len: usize = 0,
        pub fn push(self: *@This(), value: T) void {
            self.items[self.head] = value;
            self.head = (self.head + 1) % N;
            self.len = @min(self.len + 1, N);
        }
        pub fn at(self: *const @This(), index: usize) *const T {
            return &self.items[(self.head + N - self.len + index) % N];
        }
    };
}
pub const Acc = struct {
    ts: u64 = 0,
    count: u32 = 0,
    sums: [M.metric_count]i64 = @splat(0),
    counts: [M.metric_count]u32 = @splat(0),
    cpu_min: u16 = 0,
    cpu_max: u16 = 0,
    gpu_min: u16 = 0,
    gpu_max: u16 = 0,
    pub fn add(self: *Acc, s: M.Sample) void {
        if (self.count == 0) self.ts = s.ts_wall_ms;
        self.count += 1;
        for (s.values, 0..) |v, i| {
            if (s.available & (@as(u32, 1) << @intCast(i)) == 0) continue;
            self.sums[i] += v;
            self.counts[i] += 1;
        }
        if (s.get(.cpu_pct_x10)) |v| {
            const u: u16 = @intCast(std.math.clamp(v, 0, 1000));
            self.cpu_min = if (self.counts[0] == 1) u else @min(self.cpu_min, u);
            self.cpu_max = @max(self.cpu_max, u);
        }
        if (s.get(.gpu_pct)) |v| {
            const u: u16 = @intCast(std.math.clamp(v, 0, 100));
            self.gpu_min = if (self.counts[2] == 1) u else @min(self.gpu_min, u);
            self.gpu_max = @max(self.gpu_max, u);
        }
    }
    pub fn finish(self: *Acc) M.Agg {
        var out = M.Agg{ .ts_wall_ms = self.ts, .count = self.count, .cpu_min = self.cpu_min, .cpu_max = self.cpu_max, .gpu_min = self.gpu_min, .gpu_max = self.gpu_max };
        for (self.sums, self.counts, 0..) |sum, count, i| if (count > 0) {
            out.available |= @as(u32, 1) << @intCast(i);
            out.values[i] = @intCast(@divTrunc(sum, count));
        };
        self.* = .{};
        return out;
    }
};
pub const Store = struct {
    hi: Ring(M.Sample, 1800) = .{},
    mid: Ring(M.Agg, 2160) = .{},
    lo: Ring(M.Agg, 10080) = .{},
    mid_acc: Acc = .{},
    lo_acc: Acc = .{},
    mid_bucket: ?u64 = null,
    lo_bucket: ?u64 = null,
    last_mono: u64 = 0,
    last_wall: u64 = 0,
    clock_changes: u64 = 0,
    gaps: u64 = 0,
    pub fn push(self: *Store, s: M.Sample, mono_ms: u64) ?M.Agg {
        var flushed: ?M.Agg = null;
        if (self.last_wall != 0) {
            const wall_delta = @as(i128, s.ts_wall_ms) - self.last_wall;
            const mono_delta = mono_ms -| self.last_mono;
            if (@abs(wall_delta - mono_delta) > 2000 or mono_delta > 15000) {
                if (@abs(wall_delta - mono_delta) > 2000) self.clock_changes += 1 else self.gaps += 1;
                flushed = self.flush();
                self.mid_bucket = null;
                self.lo_bucket = null;
            }
        }
        const mid = mono_ms / 10000;
        const low = mono_ms / 60000;
        if (self.mid_bucket != null and self.mid_bucket.? != mid and self.mid_acc.count > 0)
            self.mid.push(self.mid_acc.finish());
        if (self.lo_bucket != null and self.lo_bucket.? != low and self.lo_acc.count > 0) {
            const out = self.lo_acc.finish();
            self.lo.push(out);
            flushed = out;
        }
        self.mid_bucket = mid;
        self.lo_bucket = low;
        self.hi.push(s);
        self.mid_acc.add(s);
        self.lo_acc.add(s);
        self.last_mono = mono_ms;
        self.last_wall = s.ts_wall_ms;
        return flushed;
    }
    pub fn flush(self: *Store) ?M.Agg {
        if (self.mid_acc.count > 0) self.mid.push(self.mid_acc.finish());
        if (self.lo_acc.count == 0) return null;
        const out = self.lo_acc.finish();
        self.lo.push(out);
        return out;
    }
};
test "ring chronological wrap" {
    var ring = Ring(u32, 4){};
    for (0..7) |i| ring.push(@intCast(i));
    try std.testing.expectEqual(@as(u32, 3), ring.at(0).*);
    try std.testing.expectEqual(@as(u32, 6), ring.at(3).*);
}
test "each metric uses its own availability denominator" {
    var a = Acc{};
    var s = M.Sample{};
    s.set(.gpu_pct, 40);
    a.add(s);
    a.add(.{});
    const out = a.finish();
    try std.testing.expectEqual(@as(i32, 40), out.values[2]);
    try std.testing.expectEqual(@as(u16, 40), out.gpu_min);
}
test "2 second interval still yields 10 second and minute windows" {
    const st = try std.testing.allocator.create(Store);
    defer std.testing.allocator.destroy(st);
    st.* = .{};
    var i: u64 = 0;
    while (i <= 60000) : (i += 2000) {
        _ = st.push(.{ .ts_wall_ms = 1000000 + i }, i);
    }
    try std.testing.expectEqual(@as(usize, 6), st.mid.len);
    try std.testing.expectEqual(@as(usize, 1), st.lo.len);
    try std.testing.expectEqual(@as(u32, 30), st.lo.at(0).count);
    try std.testing.expect(@sizeOf(Store) < 2 * 1024 * 1024);
}
test "clock jumps cannot blend distant samples" {
    const st = try std.testing.allocator.create(Store);
    defer std.testing.allocator.destroy(st);
    st.* = .{};
    _ = st.push(.{ .ts_wall_ms = 100000 }, 1000);
    _ = st.push(.{ .ts_wall_ms = 100 }, 2000);
    try std.testing.expectEqual(@as(u64, 1), st.clock_changes);
    try std.testing.expectEqual(@as(u32, 1), st.lo_acc.count);
}
