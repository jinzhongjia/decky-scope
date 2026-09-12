const std = @import("std");
const M = @import("model.zig");
const Events = @import("history_events.zig");
const Span = struct { from: u64, to: u64, step: u64 = 0 };
pub const Recent = struct { ring: *const @import("store.zig").Ring(M.Sample, 1800), step: u64 };
fn less(_: void, a: Span, b: Span) bool {
    return a.from < b.from;
}
pub fn write(w: *std.Io.Writer, ring: anytype, from: u64, to: u64, metric: M.Metric, step: u64, events: *const Events.Log) !void {
    return extended(w, ring, from, to, metric, step, events, null);
}
pub fn extended(w: *std.Io.Writer, ring: anytype, from: u64, to: u64, metric: M.Metric, step: u64, events: *const Events.Log, recent: ?Recent) !void {
    var spans: [11880]Span = undefined;
    var valid: usize = 0;
    var records: usize = 0;
    var live_records: usize = 0;
    var first: ?u64 = null;
    var last: ?u64 = null;
    for (0..ring.len) |i| {
        const p = ring.at(i);
        if (p.ts_wall_ms > to or p.ts_wall_ms +| step <= from) continue;
        records += 1;
        if (p.available & M.bit(metric) == 0) continue;
        first = @min(first orelse p.ts_wall_ms, p.ts_wall_ms);
        last = @max(last orelse 0, p.ts_wall_ms);
        spans[valid] = .{ .from = @max(from, p.ts_wall_ms), .to = @min(to, p.ts_wall_ms +| step), .step = step };
        valid += 1;
    }
    const tier_valid = valid;
    if (recent) |tail| for (0..tail.ring.len) |i| {
        const p = tail.ring.at(i);
        if (p.ts_wall_ms > to or p.ts_wall_ms +| tail.step <= from or p.available & M.bit(metric) == 0) continue;
        first = @min(first orelse p.ts_wall_ms, p.ts_wall_ms);
        last = @max(last orelse 0, p.ts_wall_ms);
        spans[valid] = .{ .from = @max(from, p.ts_wall_ms), .to = @min(to, p.ts_wall_ms +| tail.step), .step = tail.step };
        valid += 1;
        live_records += 1;
    };
    std.mem.sort(Span, spans[0..valid], {}, less);
    var gaps: [256]Span = undefined;
    var gap_len: usize = 0;
    var truncated = false;
    var cursor = from;
    var covered: u64 = 0;
    var previous_step: u64 = 0;
    for (spans[0..valid]) |span| {
        // Small cadence jitter is not a missing interval; never bridge a large gap.
        if (span.from > cursor and previous_step > 0 and span.from - cursor <= @min(previous_step, span.step) / 2) {
            covered += span.from - cursor;
            cursor = span.from;
        }
        if (span.from > cursor) {
            if (gap_len < gaps.len) {
                gaps[gap_len] = .{ .from = cursor, .to = span.from };
                gap_len += 1;
            } else truncated = true;
        }
        covered += span.to -| @max(cursor, span.from);
        if (span.to >= cursor) previous_step = span.step;
        cursor = @max(cursor, span.to);
    }
    if (cursor < to) {
        if (gap_len < gaps.len) {
            gaps[gap_len] = .{ .from = cursor, .to = to };
            gap_len += 1;
        } else truncated = true;
    }
    covered = @min(covered, to -| from);
    try w.print(",\"coverage\":{{\"estimated\":true,\"from_ms\":{d},\"to_ms\":{d},\"source_records\":{d},\"valid_records\":{d},\"live_records\":{d},\"estimated_covered_ms\":{d},\"uncovered_ms\":{d},\"truncated\":{},\"first_ms\":", .{ from, to, records, tier_valid, live_records, covered, (to -| from) - covered, truncated });
    if (first) |v| try w.print("{d}", .{v}) else try w.writeAll("null");
    try w.writeAll(",\"last_ms\":");
    if (last) |v| try w.print("{d}", .{v}) else try w.writeAll("null");
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

test "recent samples cover pending aggregate tail and overlap query boundary" {
    var low: @import("store.zig").Ring(M.Sample, 8) = .{};
    var p = M.Sample{ .ts_wall_ms = 1000 };
    p.set(.gpu_pct, 0);
    low.push(p);
    var recent: @import("store.zig").Ring(M.Sample, 1800) = .{};
    for ([_]u64{ 61000, 62000, 63000 }) |stamp| {
        p.ts_wall_ms = stamp;
        recent.push(p);
    }
    var buffer: [8192]u8 = undefined;
    var w = std.Io.Writer.fixed(&buffer);
    try extended(&w, &low, 2000, 64000, .gpu_pct, 60000, &.{}, .{ .ring = &recent, .step = 1000 });
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "\"estimated_covered_ms\":62000") != null);
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "\"uncovered_ms\":0") != null);
}
