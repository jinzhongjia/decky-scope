const std = @import("std");
const sys = @import("sys.zig");
pub var root: []const u8 = "";
pub fn path(buf: []u8, suffix: []const u8) ?[:0]const u8 {
    return std.fmt.bufPrintZ(buf, "{s}{s}", .{ root, suffix }) catch null;
}
pub fn open(suffix: []const u8) !i32 {
    var buf: [1024]u8 = undefined;
    return sys.open(path(&buf, suffix) orelse return error.PathTooLong);
}
pub fn text(suffix: []const u8, buf: []u8) ?[]const u8 {
    const fd = open(suffix) catch return null;
    defer sys.close(fd);
    const n = sys.pread(fd, buf, 0) catch return null;
    return std.mem.trim(u8, buf[0..n], " \t\r\n");
}
pub fn integer(s: []const u8) ?i64 {
    return std.fmt.parseInt(i64, s, 10) catch null;
}
pub const Value = struct {
    fd: i32 = -1,
    pub fn init(p: []const u8) Value {
        return .{ .fd = open(p) catch -1 };
    }
    pub fn close(self: *Value) void {
        if (self.fd >= 0) sys.close(self.fd);
        self.fd = -1;
    }
    pub fn read(self: Value, buf: []u8) ?[]const u8 {
        if (self.fd < 0) return null;
        const n = sys.pread(self.fd, buf, 0) catch return null;
        if (n == 0) return null;
        return std.mem.trim(u8, buf[0..n], " \t\r\n");
    }
    pub fn int(self: Value) ?i64 {
        var buf: [64]u8 = undefined;
        return integer(self.read(&buf) orelse return null);
    }
};
pub fn dir(suffix: []const u8) !sys.DirIter {
    var buf: [1024]u8 = undefined;
    return sys.DirIter.open(path(&buf, suffix) orelse return error.PathTooLong);
}
pub fn join(buf: []u8, comptime fmt: []const u8, args: anytype) ?[]const u8 {
    return std.fmt.bufPrint(buf, fmt, args) catch null;
}
