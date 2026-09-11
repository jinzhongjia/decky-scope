const std = @import("std");
const M = @import("model.zig");
const Store = @import("store.zig").Store;
pub const MAX_LINE = 256 * 1024;
pub const Args = struct {
    live_push: ?bool = null,
    interval_ms: ?u32 = null,
    from: u64 = 0,
    to: u64 = std.math.maxInt(u64),
    max_points: u16 = 300,
    metric: M.Metric = .cpu_pct_x10,
};
pub const Request = struct { type: enum { request }, id: u32, method: []const u8, args: Args = .{} };
pub fn parse(line: []const u8, memory: []u8) !Request {
    if (line.len >= MAX_LINE) return error.LineTooLong;
    var allocator = std.heap.FixedBufferAllocator.init(memory);
    const req = try std.json.parseFromSliceLeaky(Request, allocator.allocator(), line, .{ .ignore_unknown_fields = false, .max_value_len = 1024 });
    if (req.args.interval_ms) |v| if (v < 500 or v > 5000) return error.InvalidInterval;
    if (req.args.from > req.args.to or req.args.max_points == 0 or req.args.max_points > 1200) return error.InvalidRange;
    return req;
}
pub fn requestId(line: []const u8, memory: []u8) ?u32 {
    var allocator = std.heap.FixedBufferAllocator.init(memory);
    const Head = struct { id: ?u32 = null };
    const head = std.json.parseFromSliceLeaky(Head, allocator.allocator(), line, .{ .ignore_unknown_fields = true }) catch return null;
    return head.id;
}
pub fn string(w: *std.Io.Writer, text: []const u8) !void {
    try w.writeByte('"');
    for (text) |c| switch (c) {
        '"', '\\' => {
            try w.writeByte('\\');
            try w.writeByte(c);
        },
        0...31 => try w.print("\\u00{x:0>2}", .{c}),
        else => try w.writeByte(c),
    };
    try w.writeByte('"');
}
pub fn failure(w: *std.Io.Writer, id: ?u32, code: []const u8) !void {
    try w.writeAll("{\"type\":\"response\",\"id\":");
    if (id) |n| try w.print("{d}", .{n}) else try w.writeAll("null");
    try w.writeAll(",\"ok\":false,\"error\":{\"code\":");
    try string(w, code);
    try w.writeAll(",\"message\":\"Request could not be completed\"}}\n");
}
pub fn history(w: *std.Io.Writer, st: *const Store, a: Args) !void {
    const span = a.to -| a.from;
    const hi_covered = st.hi.len > 0 and a.from >= st.hi.at(0).ts_wall_ms;
    const mid_covered = st.mid.len > 0 and a.from >= st.mid.at(0).ts_wall_ms;
    const resolution: u32 = if (span <= 1800000 and (hi_covered or (st.mid.len == 0 and st.lo.len == 0))) 1000 else if (span <= 21600000 and (mid_covered or st.lo.len == 0)) 10000 else 60000;
    try w.print("{{\"resolution_ms\":{d},\"metric\":\"{s}\",\"samples\":[", .{ resolution, @tagName(a.metric) });
    switch (resolution) {
        1000 => try points(w, &st.hi, a, false),
        10000 => try points(w, &st.mid, a, true),
        else => try points(w, &st.lo, a, true),
    }
    try w.writeAll("]}");
}
fn points(w: *std.Io.Writer, ring: anytype, a: Args, comptime agg: bool) !void {
    var count: usize = 0;
    for (0..ring.len) |i| {
        const s = ring.at(i);
        if (s.ts_wall_ms >= a.from and s.ts_wall_ms <= a.to) count += 1;
    }
    const stride = @max(1, (count + a.max_points - 1) / a.max_points);
    var seen: usize = 0;
    var emitted: usize = 0;
    for (0..ring.len) |i| {
        const s = ring.at(i);
        if (s.ts_wall_ms < a.from or s.ts_wall_ms > a.to) continue;
        const index = seen;
        seen += 1;
        if (index % stride != 0) continue;
        if (emitted > 0) try w.writeByte(',');
        emitted += 1;
        try w.print("{{\"ts_wall_ms\":{d},\"value\":", .{s.ts_wall_ms});
        if (s.available & M.bit(a.metric) != 0) {
            try w.print("{d}", .{s.values[@intFromEnum(a.metric)]});
            if (agg and (a.metric == .cpu_pct_x10 or a.metric == .gpu_pct))
                try w.print(",\"min\":{d},\"max\":{d}", .{ if (a.metric == .gpu_pct) s.gpu_min else s.cpu_min, if (a.metric == .gpu_pct) s.gpu_max else s.cpu_max });
        } else try w.writeAll("null");
        try w.writeByte('}');
    }
}
test "strict requests reject malformed types duplicates and trailing input" {
    var memory: [16384]u8 = undefined;
    const bad = [_][]const u8{
        "{}",                                                                            "{\"type\":\"request\",\"method\":\"get_status\"}",
        "{\"type\":\"request\",\"id\":1.5,\"method\":\"get_status\"}",                   "{\"type\":\"request\",\"id\":-1,\"method\":\"get_status\"}",
        "{\"type\":\"request\",\"id\":1,\"id\":2,\"method\":\"get_status\"}",            "{\"type\":\"request\",\"id\":1,\"method\":\"x\",\"args\":{\"max_points\":1201}}",
        "{\"type\":\"request\",\"id\":1,\"method\":\"x\",\"args\":{\"interval_ms\":0}}", "{\"type\":\"request\",\"id\":1,\"method\":\"x\"} trailing",
    };
    for (bad) |line| {
        if (parse(line, &memory)) |_| return error.AcceptedInvalidRequest else |_| {}
    }
}
test "valid JSON escaped method is decoded" {
    var memory: [16384]u8 = undefined;
    const req = try parse("{\"type\":\"request\",\"id\":9,\"method\":\"get_\\u0073tatus\"}", &memory);
    try std.testing.expectEqualStrings("get_status", req.method);
}
