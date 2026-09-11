const std = @import("std");
const src = @import("source.zig");
const State = enum { unknown, not_listening, loopback_only, non_loopback_listener };
pub fn probe(text: []const u8, port: u16, ipv6: bool) State {
    var result: State = .not_listening;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        var words = std.mem.tokenizeAny(u8, line, " \t");
        _ = words.next() orelse continue;
        const local = words.next() orelse continue;
        _ = words.next() orelse continue;
        if (!std.mem.eql(u8, words.next() orelse continue, "0A")) continue;
        const colon = std.mem.indexOfScalar(u8, local, ':') orelse continue;
        const p = std.fmt.parseInt(u16, local[colon + 1 ..], 16) catch continue;
        if (p != port) continue;
        const addr = local[0..colon];
        const loop = if (ipv6) std.mem.eql(u8, addr, "00000000000000000000000001000000") else addr.len == 8 and std.mem.eql(u8, addr[6..], "7F");
        if (!loop) return .non_loopback_listener;
        result = .loopback_only;
    }
    return result;
}
pub fn write(w: *std.Io.Writer) !void {
    var buf: [65536]u8 = undefined;
    var ssh: State = .unknown;
    var cef: State = .unknown;
    inline for (.{ "/proc/net/tcp", "/proc/net/tcp6" }, 0..) |path, i| {
        if (src.text(path, &buf)) |text| {
            ssh = @enumFromInt(@max(@intFromEnum(ssh), @intFromEnum(probe(text, 22, i == 1))));
            cef = @enumFromInt(@max(@intFromEnum(cef), @intFromEnum(probe(text, 8080, i == 1))));
        }
    }
    try w.print(",\"ssh\":\"{s}\",\"cef\":\"{s}\",\"reachability_verified\":false", .{ @tagName(ssh), @tagName(cef) });
}
test "listening address is not a promise of firewall reachability" {
    try std.testing.expectEqual(State.loopback_only, probe("0: 0100007F:1F90 00000000:0000 0A", 8080, false));
    try std.testing.expectEqual(State.non_loopback_listener, probe("0: 00000000:0016 00000000:0000 0A", 22, false));
    try std.testing.expectEqual(State.not_listening, probe("0: 00000000:0016 00000000:0000 01", 22, false));
}
