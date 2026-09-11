const std = @import("std");
const src = @import("source.zig");
const proto = @import("protocol.zig");
const M = @import("model.zig");
pub const Device = struct {
    board: [128]u8 = @splat(0),
    bios: [128]u8 = @splat(0),
    kernel: [128]u8 = @splat(0),
    os_name: [128]u8 = @splat(0),
    os_id: [64]u8 = @splat(0),
    os_version: [64]u8 = @splat(0),
    os_build: [64]u8 = @splat(0),
    pub fn init() Device {
        var self = Device{};
        read(&self.board, "/sys/class/dmi/id/board_name");
        read(&self.bios, "/sys/class/dmi/id/bios_version");
        read(&self.kernel, "/proc/sys/kernel/osrelease");
        var buf: [8192]u8 = undefined;
        const text = src.text("/etc/os-release", &buf) orelse "";
        copy(&self.os_name, field(text, "PRETTY_NAME") orelse "Unknown");
        copy(&self.os_id, field(text, "ID") orelse "unknown");
        copy(&self.os_version, field(text, "VERSION_ID") orelse "");
        copy(&self.os_build, field(text, "BUILD_ID") orelse "");
        return self;
    }
    pub fn write(self: *const Device, w: *std.Io.Writer) !void {
        try w.writeAll("{\"monitor_version\":\"" ++ M.version ++ "\",\"arch\":\"x86_64\"");
        inline for (.{ "board", "bios", "kernel", "os_name", "os_id", "os_version", "os_build" }) |key| {
            try w.writeAll(",\"" ++ key ++ "\":");
            try proto.string(w, z(&@field(self, key)));
        }
        const board = z(&self.board);
        try w.writeAll(",\"profile\":");
        try proto.string(w, if (std.mem.eql(u8, board, "Jupiter")) "steam_deck_lcd" else if (std.mem.eql(u8, board, "Galileo")) "steam_deck_oled" else if (std.mem.eql(u8, z(&self.os_id), "steamos")) "generic_steamos" else "generic_linux");
        try w.print(",\"is_steamos\":{},\"compatibility_verified\":false}}", .{std.mem.eql(u8, z(&self.os_id), "steamos")});
    }
};
pub fn z(bytes: []const u8) []const u8 {
    return bytes[0 .. std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len];
}
fn copy(dest: []u8, value: []const u8) void {
    @memset(dest, 0);
    const n = @min(dest.len - 1, value.len);
    @memcpy(dest[0..n], value[0..n]);
}
fn read(dest: []u8, path: []const u8) void {
    var buf: [256]u8 = undefined;
    copy(dest, src.text(path, &buf) orelse "");
}
pub fn field(text: []const u8, key: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (line.len <= key.len or !std.mem.startsWith(u8, line, key) or line[key.len] != '=') continue;
        return std.mem.trim(u8, line[key.len + 1 ..], "\"' \r");
    }
    return null;
}
test "os release parser matches complete keys" {
    try std.testing.expectEqualStrings("3.8", field("VERSION_ID=\"3.8\"\nBUILD_ID=2026", "VERSION_ID").?);
    try std.testing.expect(field("VERSION_ID=3.8", "VERSION") == null);
}
