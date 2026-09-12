const std = @import("std");
const M = @import("model.zig");
const Events = @import("history_events.zig");
const Span = struct { from: u64, to: u64 };
fn less(_: void, a: u64, b: u64) bool {
    return a < b;
}
pub fn write(w: *std.Io.Writer, ring: anytype, from: u64, to: u64, metric: M.Metric, step: u64, events: *const Events.Log) !void {
    // Sort bounded timestamps so wall-clock rollback cannot double-count coverage.
    var times: [10080]u64 = undefined;
    var valid: usize = 0;
    var records: usize = 0;
    for (0..ring.len) |i| {
        const p = ring.at(i);
        if (p.ts_wall_ms < from or p.ts_wall_ms > to) continue;
        records += 1;
        if (p.available & M.bit(metric) != 0 and valid < times.len) {
            times[valid] = p.ts_wall_ms;
            valid += 1;
        }
    }
    std.mem.sort(u64, times[0..valid], {}, less);
    var gaps: [256]Span = undefined;
    var gap_len: usize = 0;
    var truncated = false;
    var cursor = from;
    var covered: u64 = 0;
    for (times[0..valid], 0..) |stamp, i| {
        var end = @min(to, stamp +| step);
        if (i + 1 < valid and times[i + 1] > stamp and times[i + 1] - stamp <= step + step / 2) end = @min(to, times[i + 1]);
        if (stamp > cursor) {
            if (gap_len < gaps.len) {
                gaps[gap_len] = .{ .from = cursor, .to = stamp };
                gap_len += 1;
            } else truncated = true;
        }
        covered += end -| @max(cursor, stamp);
        cursor = @max(cursor, end);
    }
    if (cursor < to) {
        if (gap_len < gaps.len) {
            gaps[gap_len] = .{ .from = cursor, .to = to };
            gap_len += 1;
        } else truncated = true;
    }
    covered = @min(covered, to -| from);
    try w.print(",\"coverage\":{{\"estimated\":true,\"from_ms\":{d},\"to_ms\":{d},\"source_records\":{d},\"valid_records\":{d},\"estimated_covered_ms\":{d},\"uncovered_ms\":{d},\"truncated\":{},\"first_ms\":", .{ from, to, records, valid, covered, (to -| from) - covered, truncated });
    if (valid > 0) try w.print("{d}", .{times[0]}) else try w.writeAll("null");
    try w.writeAll(",\"last_ms\":");
    if (valid > 0) try w.print("{d}", .{times[valid - 1]}) else try w.writeAll("null");
    try w.writeAll(",\"gaps\":[");
    for (gaps[0..gap_len], 0..) |g, i| {
        if (i > 0) try w.writeByte(',');
        try w.print("{{\"from_ms\":{d},\"to_ms\":{d},\"kind\":\"no_data\"}}", .{ g.from, g.to });
    }
    try w.writeAll("]},\"events\":[");
    var emitted: usize = 0;
    for (events.items[0..events.len]) |e| {
        if (@max(e.from_ms, e.to_ms) < from or @min(e.from_ms, e.to_ms) > to) continue;
        if (emitted > 0) try w.writeByte(',');
        try w.print("{{\"kind\":\"{s}\",\"from_ms\":{d},\"to_ms\":{d},\"estimated\":true}}", .{ @tagName(e.kind), e.from_ms, e.to_ms });
        emitted += 1;
    }
    try w.print("],\"events_truncated\":{},\"events_persistence_failed\":{}", .{ events.truncated, events.failed });
}
test "coverage distinguishes missing samples from actual zero values" {
    var ring: @import("store.zig").Ring(M.Sample, 8) = .{};
    var s = M.Sample{ .ts_wall_ms = 1000 };
    s.set(.gpu_pct, 0);
    ring.push(s);
    ring.push(.{ .ts_wall_ms = 2000 });
    s.ts_wall_ms = 10000;
    ring.push(s);
    var buffer: [8192]u8 = undefined;
    var w = std.Io.Writer.fixed(&buffer);
    try write(&w, &ring, 0, 12000, .gpu_pct, 1000, &.{});
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "\"valid_records\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "\"estimated_covered_ms\":2000") != null);
}
test "coverage sorts clock rollback and unions overlapping support" {
    var ring: @import("store.zig").Ring(M.Sample, 8) = .{};
    for ([_]u64{ 3000, 1000, 1000, 2000 }) |time| {
        var s = M.Sample{ .ts_wall_ms = time };
        s.set(.gpu_pct, 0);
        ring.push(s);
    }
    var buffer: [8192]u8 = undefined;
    var w = std.Io.Writer.fixed(&buffer);
    try write(&w, &ring, 0, 5000, .gpu_pct, 1000, &.{});
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "\"estimated_covered_ms\":3000") != null);
}
