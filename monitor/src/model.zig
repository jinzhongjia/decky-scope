const std = @import("std");
pub const version = "0.1.0-rc.2";
pub const Metric = enum(u5) {
    cpu_pct_x10,
    cpu_mhz,
    gpu_pct,
    gpu_mhz,
    mem_used_mb,
    mem_total_mb,
    swap_used_mb,
    cpu_temp_mc,
    gpu_temp_mc,
    nvme_temp_mc,
    apu_power_mw,
    battery_rate_mw,
    battery_pct,
    fan_rpm,
    psi_cpu_some_x100,
    psi_mem_some_x100,
    psi_mem_full_x100,
    psi_io_some_x100,
    psi_io_full_x100,
    disk_read_kbps,
    disk_write_kbps,
    net_rx_kbps,
    net_tx_kbps,
    net_rx_errors_delta,
    net_tx_errors_delta,
};
pub const metric_count = @typeInfo(Metric).@"enum".fields.len;
pub const Sample = extern struct {
    ts_wall_ms: u64 = 0,
    available: u32 = 0,
    values: [metric_count]i32 = @splat(0),
    pub fn set(self: *Sample, m: Metric, value: i64) void {
        const v = std.math.cast(i32, value) orelse return;
        self.values[@intFromEnum(m)] = v;
        self.available |= bit(m);
    }
    pub fn get(self: *const Sample, m: Metric) ?i32 {
        return if (self.available & bit(m) != 0) self.values[@intFromEnum(m)] else null;
    }
};
pub const Agg = extern struct {
    ts_wall_ms: u64 = 0,
    available: u32 = 0,
    values: [metric_count]i32 = @splat(0),
    cpu_min: u16 = 0,
    cpu_max: u16 = 0,
    gpu_min: u16 = 0,
    gpu_max: u16 = 0,
    count: u32 = 0,
};
pub fn bit(m: Metric) u32 {
    return @as(u32, 1) << @intFromEnum(m);
}
pub fn writeValues(w: *std.Io.Writer, s: anytype) !void {
    try w.print("{{\"ts_wall_ms\":{d},\"available\":{d}", .{ s.ts_wall_ms, s.available });
    inline for (@typeInfo(Metric).@"enum".fields) |f| {
        if (s.available & (@as(u32, 1) << f.value) != 0)
            try w.print(",\"" ++ f.name ++ "\":{d}", .{s.values[f.value]});
    }
    try w.writeAll("}");
}
test "stable sample and aggregate layout" {
    try std.testing.expectEqual(@as(usize, 112), @sizeOf(Sample));
    try std.testing.expectEqual(@as(usize, 128), @sizeOf(Agg));
    try std.testing.expectEqual(@as(usize, 12), @offsetOf(Agg, "values"));
}
test "missing and zero are distinct" {
    var s = Sample{};
    try std.testing.expect(s.get(.gpu_pct) == null);
    s.set(.gpu_pct, 0);
    try std.testing.expectEqual(@as(?i32, 0), s.get(.gpu_pct));
}
