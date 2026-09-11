//! sys.zig — 直接基于 std.os.linux 原始 syscall 的薄封装（Zig 0.16，无 libc）
//!
//! Zig 0.16 大幅重构了 std（posix 层削减、net/io 并入 std.Io 新体系）。
//! 为了让 monitor 完全不依赖仍在演进的 std.Io，本文件只依赖 std.os.linux
//! —— 它是 syscall number + 参数编排的最薄封装，也是 std 中最稳定的一层。
const std = @import("std");
const linux = std.os.linux;

pub const fd_t = linux.fd_t;

pub const Error = error{ Sys, Again, Closed };

fn check(rc: usize) Error!usize {
    if (linux.errno(rc) == .AGAIN) return error.Again;
    if (linux.errno(rc) != .SUCCESS) return error.Sys;
    return rc;
}

// ---- 文件 ----

pub fn open(path: [:0]const u8) Error!fd_t {
    const rc = try check(linux.openat(linux.AT.FDCWD, path.ptr, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0));
    return @intCast(rc);
}

pub fn pread(fd: fd_t, buf: []u8, offset: i64) Error!usize {
    return try check(linux.pread(fd, buf.ptr, buf.len, offset));
}

pub fn read(fd: fd_t, buf: []u8) Error!usize {
    return try check(linux.read(fd, buf.ptr, buf.len));
}

pub fn write(fd: fd_t, data: []const u8) Error!usize {
    return try check(linux.write(fd, data.ptr, data.len));
}

pub fn writeAll(fd: fd_t, data: []const u8) Error!void {
    var off: usize = 0;
    while (off < data.len) {
        const n = try write(fd, data[off..]);
        if (n == 0) return error.Closed;
        off += n;
    }
}

pub fn close(fd: fd_t) void {
    _ = linux.close(fd);
}

// ---- 目录遍历（getdents64，用于 hwmon/power_supply 探测） ----

pub const DirIter = struct {
    fd: fd_t,
    buf: [4096]u8 = undefined,
    len: usize = 0,
    pos: usize = 0,

    pub fn open(path: [:0]const u8) Error!DirIter {
        const rc = try check(linux.openat(linux.AT.FDCWD, path.ptr, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0));
        return .{ .fd = @intCast(rc) };
    }

    pub fn next(self: *DirIter) ?[]const u8 {
        while (true) {
            if (self.pos >= self.len) {
                const rc = linux.getdents64(self.fd, &self.buf, self.buf.len);
                if (linux.errno(rc) != .SUCCESS or rc == 0) return null;
                self.len = rc;
                self.pos = 0;
            }
            const ent: *align(1) linux.dirent64 = @ptrCast(self.buf[self.pos..].ptr);
            self.pos += ent.reclen;
            const name_ptr: [*:0]const u8 = @ptrCast(@as([*]const u8, @ptrCast(ent)) + @offsetOf(linux.dirent64, "name"));
            const name = std.mem.span(name_ptr);
            if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
            return name;
        }
    }

    pub fn deinit(self: *DirIter) void {
        close(self.fd);
    }
};

// ---- 时间 ----

pub fn nowMs() u64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1000 + @as(u64, @intCast(ts.nsec)) / 1_000_000;
}

pub fn nowUs() u64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000 + @as(u64, @intCast(ts.nsec)) / 1000;
}

// ---- UDS 客户端 ----

pub fn connectUnix(path: []const u8) Error!fd_t {
    const rc = try check(linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0));
    const fd: fd_t = @intCast(rc);
    errdefer close(fd);
    var addr = linux.sockaddr.un{ .path = @splat(0) };
    if (path.len >= addr.path.len) return error.Sys;
    @memcpy(addr.path[0..path.len], path);
    _ = try check(linux.connect(fd, &addr, @intCast(@offsetOf(linux.sockaddr.un, "path") + path.len + 1)));
    return fd;
}

// ---- timerfd ----

pub fn timerfdCreate() Error!fd_t {
    const rc = try check(linux.timerfd_create(.MONOTONIC, .{ .CLOEXEC = true }));
    return @intCast(rc);
}

pub fn timerfdSet(tfd: fd_t, interval_ms: u32) Error!void {
    const sec: isize = interval_ms / 1000;
    const nsec: isize = @as(isize, interval_ms % 1000) * 1_000_000;
    const spec = linux.itimerspec{
        .it_interval = .{ .sec = sec, .nsec = nsec },
        .it_value = .{ .sec = sec, .nsec = nsec },
    };
    _ = try check(linux.timerfd_settime(tfd, .{}, &spec, null));
}

pub fn timerfdDrain(tfd: fd_t) void {
    var b: [8]u8 = undefined;
    _ = linux.read(tfd, &b, 8);
}

// ---- epoll ----

pub const EpollEvent = linux.epoll_event;

pub fn epollCreate() Error!fd_t {
    const rc = try check(linux.epoll_create1(linux.EPOLL.CLOEXEC));
    return @intCast(rc);
}

pub fn epollAdd(efd: fd_t, fd: fd_t, tag: u32) Error!void {
    var ev = linux.epoll_event{
        .events = linux.EPOLL.IN | linux.EPOLL.RDHUP | linux.EPOLL.HUP,
        .data = .{ .u32 = tag },
    };
    _ = try check(linux.epoll_ctl(efd, linux.EPOLL.CTL_ADD, fd, &ev));
}

pub fn epollWait(efd: fd_t, events: []linux.epoll_event) usize {
    while (true) {
        const rc = linux.epoll_wait(efd, events.ptr, @intCast(events.len), -1);
        if (linux.errno(rc) == .INTR) continue;
        if (linux.errno(rc) != .SUCCESS) return 0;
        return rc;
    }
}

pub fn wallMs() u64 {
    var ts: linux.timespec = undefined;
    if (linux.errno(linux.clock_gettime(.REALTIME, &ts)) != .SUCCESS or ts.sec < 0) return 0;
    return @as(u64, @intCast(ts.sec)) * 1000 + @as(u64, @intCast(ts.nsec)) / 1000000;
}
pub fn bootMs() u64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.BOOTTIME, &ts);
    return @as(u64, @intCast(ts.sec)) * 1000 + @as(u64, @intCast(ts.nsec)) / 1000000;
}
pub const IN = linux.EPOLL.IN;
pub const OUT = linux.EPOLL.OUT;
pub fn epollInterest(efd: fd_t, fd: fd_t, tag: u32, writable: bool) Error!void {
    var ev = linux.epoll_event{ .events = IN | linux.EPOLL.RDHUP | (if (writable) OUT else @as(u32, 0)), .data = .{ .u32 = tag } };
    _ = try check(linux.epoll_ctl(efd, linux.EPOLL.CTL_MOD, fd, &ev));
}
pub fn recv(fd: fd_t, buf: []u8) Error!usize {
    while (true) {
        const rc = linux.recvfrom(fd, buf.ptr, buf.len, linux.MSG.DONTWAIT, null, null);
        if (linux.errno(rc) == .INTR) continue;
        return check(rc);
    }
}
pub fn send(fd: fd_t, bytes: []const u8) Error!usize {
    while (true) {
        const rc = linux.sendto(fd, bytes.ptr, bytes.len, linux.MSG.NOSIGNAL | linux.MSG.DONTWAIT, null, 0);
        if (linux.errno(rc) == .INTR) continue;
        return check(rc);
    }
}
pub fn mkdir(path: [:0]const u8) Error!void {
    const rc = linux.mkdirat(linux.AT.FDCWD, path.ptr, 0o700);
    if (linux.errno(rc) == .EXIST) return;
    _ = try check(rc);
}
pub fn openWrite(path: [:0]const u8) Error!fd_t {
    return @intCast(try check(linux.openat(linux.AT.FDCWD, path.ptr, .{ .ACCMODE = .RDWR, .CREAT = true, .CLOEXEC = true, .NOFOLLOW = true }, 0o600)));
}
pub fn pwriteAll(fd: fd_t, bytes: []const u8, offset: u64) Error!void {
    var n: usize = 0;
    while (n < bytes.len) {
        const rc = linux.pwrite(fd, bytes[n..].ptr, bytes.len - n, @intCast(offset + n));
        if (linux.errno(rc) == .INTR) continue;
        const wrote = try check(rc);
        if (wrote == 0) return error.Closed;
        n += wrote;
    }
}
pub fn truncate(fd: fd_t, length: u64) Error!void {
    _ = try check(linux.ftruncate(fd, @intCast(length)));
}
pub fn sync(fd: fd_t) Error!void {
    _ = try check(linux.fdatasync(fd));
}
pub fn unlink(path: [:0]const u8) Error!void {
    _ = try check(linux.unlinkat(linux.AT.FDCWD, path.ptr, 0));
}

pub fn routeSocket() Error!fd_t {
    const fd: fd_t = @intCast(try check(linux.socket(linux.AF.NETLINK, linux.SOCK.RAW | linux.SOCK.CLOEXEC | linux.SOCK.NONBLOCK, 0)));
    errdefer close(fd);
    const address = linux.sockaddr.nl{ .pid = 0, .groups = 1 | 0x10 | 0x100 | 0x40 | 0x400 };
    _ = try check(linux.bind(fd, @ptrCast(&address), @sizeOf(linux.sockaddr.nl)));
    return fd;
}
pub fn routeDump(fd: fd_t, kind: u16, seq: u32) Error!void {
    var b: [32]u8 = @splat(0);
    const len: u32 = if (kind == 18) 32 else if (kind == 22) 24 else 28;
    std.mem.writeInt(u32, b[0..4], len, .little);
    std.mem.writeInt(u16, b[4..6], kind, .little);
    std.mem.writeInt(u16, b[6..8], 0x301, .little);
    std.mem.writeInt(u32, b[8..12], seq, .little);
    const address = linux.sockaddr.nl{ .pid = 0, .groups = 0 };
    _ = try check(linux.sendto(fd, &b, len, linux.MSG.DONTWAIT, @ptrCast(&address), @sizeOf(linux.sockaddr.nl)));
}

pub fn lock(fd: fd_t) Error!void {
    _ = try check(linux.flock(fd, 2 | 4));
}
