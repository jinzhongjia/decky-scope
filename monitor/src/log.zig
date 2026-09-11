//! log.zig — 极简 stderr 日志（不使用 std.debug.print）
//!
//! std.debug.print 会把 std.fmt 的完整格式化机架、panic/unwind 支持链拖进二进制。
//! monitor 的诊断输出只需要"字符串 + 少量整数"，手写拼接即可，
//! 且所有输出都经由 sys.zig 的 write syscall 直达 stderr。
const sys = @import("sys.zig");

const STDERR: i32 = 2;

/// 输出一段或多段字符串（自动补换行）
pub fn msg(parts: []const []const u8) void {
    var buf: [512]u8 = undefined;
    var len: usize = 0;
    for (parts) |p| {
        const n = @min(p.len, buf.len - 1 - len);
        @memcpy(buf[len .. len + n], p[0..n]);
        len += n;
        if (len >= buf.len - 1) break;
    }
    buf[len] = '\n';
    sys.writeAll(STDERR, buf[0 .. len + 1]) catch {};
}

/// 无符号整数转十进制字符串（写入 buf，返回切片）
pub fn fmtUint(buf: []u8, v: u64) []const u8 {
    if (v == 0) {
        buf[0] = '0';
        return buf[0..1];
    }
    var tmp: [20]u8 = undefined;
    var n: usize = 0;
    var x = v;
    while (x > 0) : (x /= 10) {
        tmp[n] = @intCast('0' + x % 10);
        n += 1;
    }
    for (0..n) |i| buf[i] = tmp[n - 1 - i];
    return buf[0..n];
}

/// bool 转字符串
pub fn fmtBool(v: bool) []const u8 {
    return if (v) "yes" else "no";
}
