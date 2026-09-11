const std = @import("std");
pub const nvme_period_us: u64 = 30_000_000;

pub fn refreshDue(last_us: ?u64, now_us: u64) bool {
    return last_us == null or now_us -| last_us.? >= nvme_period_us;
}

pub fn batteryPowerMw(state: []const u8, power_uw: ?i64, current_ua: ?i64, voltage_uv: ?i64) ?i64 {
    if (std.mem.eql(u8, state, "Full") or std.mem.eql(u8, state, "Not charging")) return 0;
    const charging = std.mem.eql(u8, state, "Charging");
    if (!charging and !std.mem.eql(u8, state, "Discharging")) return null;
    var mw: i128 = undefined;
    if (power_uw != null and power_uw.? >= 0) {
        mw = @divTrunc(power_uw.?, 1000);
    } else {
        const current = current_ua orelse return null;
        const voltage = voltage_uv orelse return null;
        if (voltage <= 0) return null;
        // microamp * microvolt / 1e9 -> milliwatt; i128 prevents overflow.
        const magnitude: i128 = @intCast(@abs(@as(i128, current)));
        mw = @divTrunc(magnitude * voltage, 1_000_000_000);
    }
    if (mw > std.math.maxInt(i32)) return null;
    return @intCast(if (charging) -mw else mw);
}

test "battery prefers power_now and otherwise derives from current and voltage" {
    try std.testing.expectEqual(@as(?i64, 14000), batteryPowerMw("Discharging", 14000000, 2000000, 8000000));
    try std.testing.expectEqual(@as(?i64, 16000), batteryPowerMw("Discharging", null, 2000000, 8000000));
    try std.testing.expectEqual(@as(?i64, -16000), batteryPowerMw("Charging", null, -2000000, 8000000));
    try std.testing.expectEqual(@as(?i64, 0), batteryPowerMw("Not charging", null, null, null));
}
test "unknown or impossible battery readings remain unavailable" {
    try std.testing.expectEqual(@as(?i64, null), batteryPowerMw("Unknown", 1000000, 1000000, 8000000));
    try std.testing.expectEqual(@as(?i64, null), batteryPowerMw("Discharging", null, null, 8000000));
    try std.testing.expectEqual(@as(?i64, null), batteryPowerMw("Discharging", null, 1000000, 0));
    try std.testing.expectEqual(@as(?i64, null), batteryPowerMw("Charging", null, std.math.minInt(i64), std.math.maxInt(i64)));
}
test "NVMe cadence uses monotonic time, not configurable sample count" {
    try std.testing.expect(refreshDue(null, 1));
    try std.testing.expect(!refreshDue(1, 30_000_000));
    try std.testing.expect(refreshDue(1, 30_000_001));
}
