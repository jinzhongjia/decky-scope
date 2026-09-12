const std = @import("std");
const sys = @import("sys.zig");
const M = @import("model.zig");
const Store = @import("store.zig").Store;
pub const record_size = 128;
const header_size = 32;
const day_ms = 86400000;
const max_records = 2880; // bounded even under repeated short restarts
pub fn encode(a: M.Agg) [record_size]u8 {
    var bytes: [record_size]u8 = @splat(0);
    std.mem.writeInt(u64, bytes[0..8], a.ts_wall_ms, .little);
    std.mem.writeInt(u32, bytes[8..12], a.available, .little);
    for (a.values, 0..) |v, i| std.mem.writeInt(i32, bytes[12 + i * 4 ..][0..4], v, .little);
    std.mem.writeInt(u16, bytes[112..114], a.cpu_min, .little);
    std.mem.writeInt(u16, bytes[114..116], a.cpu_max, .little);
    std.mem.writeInt(u16, bytes[116..118], a.gpu_min, .little);
    std.mem.writeInt(u16, bytes[118..120], a.gpu_max, .little);
    std.mem.writeInt(u32, bytes[120..124], a.count, .little);
    std.mem.writeInt(u32, bytes[124..128], std.hash.Crc32.hash(bytes[0..124]), .little);
    return bytes;
}
pub fn decode(bytes: *const [record_size]u8) ?M.Agg {
    if (std.mem.readInt(u32, bytes[124..128], .little) != std.hash.Crc32.hash(bytes[0..124])) return null;
    var out = M.Agg{ .ts_wall_ms = std.mem.readInt(u64, bytes[0..8], .little), .available = std.mem.readInt(u32, bytes[8..12], .little) };
    if (out.available >> M.metric_count != 0) return null;
    for (&out.values, 0..) |*v, i| v.* = std.mem.readInt(i32, bytes[12 + i * 4 ..][0..4], .little);
    out.cpu_min = std.mem.readInt(u16, bytes[112..114], .little);
    out.cpu_max = std.mem.readInt(u16, bytes[114..116], .little);
    out.gpu_min = std.mem.readInt(u16, bytes[116..118], .little);
    out.gpu_max = std.mem.readInt(u16, bytes[118..120], .little);
    out.count = std.mem.readInt(u32, bytes[120..124], .little);
    if (out.count == 0 or out.count > 10000) return null;
    return out;
}
fn header(day: u64) [header_size]u8 {
    var b: [header_size]u8 = @splat(0);
    @memcpy(b[0..4], "DSCP");
    std.mem.writeInt(u16, b[4..6], 1, .little);
    std.mem.writeInt(u16, b[6..8], record_size, .little);
    std.mem.writeInt(u64, b[8..16], day, .little);
    std.mem.writeInt(u32, b[16..20], (@as(u32, 1) << M.metric_count) - 1, .little);
    std.mem.writeInt(u32, b[28..32], std.hash.Crc32.hash(b[0..28]), .little);
    return b;
}
pub const Persistence = struct {
    directory: []const u8,
    lock_fd: i32 = -1,
    file_fd: i32 = -1,
    file_day: ?u64 = null,
    offset: u64 = header_size,
    lock_conflict: bool = false,
    pending: [10]M.Agg = std.mem.zeroes([10]M.Agg),
    len: usize = 0,
    failed: bool = false,
    bytes_written: u64 = 0,
    invalid_files: u32 = 0,
    last_persisted_sample_ms: ?u64 = null,
    last_sync_ms: ?u64 = null,
    last_cleanup_day: ?u64 = null,
    fn path(self: *const Persistence, buf: []u8, day: u64) ![:0]const u8 {
        return std.fmt.bufPrintZ(buf, "{s}/{d}.dscp", .{ self.directory, day });
    }
    pub fn restore(self: *Persistence, st: *Store, now: u64) void {
        var buf: [1024]u8 = undefined;
        const d = std.fmt.bufPrintZ(&buf, "{s}", .{self.directory}) catch {
            self.failed = true;
            return;
        };
        sys.mkdir(d) catch {
            self.failed = true;
            return;
        };
        const lock_path = std.fmt.bufPrintZ(&buf, "{s}/.monitor.lock", .{self.directory}) catch {
            self.failed = true;
            return;
        };
        self.lock_fd = sys.openWrite(lock_path) catch {
            self.failed = true;
            return;
        };
        sys.lock(self.lock_fd) catch {
            self.failed = true;
            self.lock_conflict = true;
            return;
        };
        const today = now / day_ms;
        for (0..7) |i| {
            const day = today -| (6 - i);
            const file = self.path(&buf, day) catch continue;
            const fd = sys.open(file) catch continue;
            defer sys.close(fd);
            var h: [header_size]u8 = undefined;
            const n = sys.pread(fd, &h, 0) catch continue;
            if (n != header_size or !std.mem.eql(u8, &h, &header(day))) {
                self.invalid_files += 1;
                continue;
            }
            var bytes: [record_size]u8 = undefined;
            for (0..max_records) |j| {
                const size = sys.pread(fd, &bytes, @intCast(header_size + j * record_size)) catch break;
                if (size == 0) break;
                if (size != record_size) {
                    self.invalid_files += 1;
                    break;
                }
                const a = decode(&bytes) orelse {
                    self.invalid_files += 1;
                    break;
                };
                if (a.ts_wall_ms / day_ms != day) {
                    self.invalid_files += 1;
                    break;
                }
                st.lo.push(a);
                self.last_persisted_sample_ms = @max(self.last_persisted_sample_ms orelse 0, a.ts_wall_ms);
            }
        }
        self.cleanup(today);
    }
    pub fn add(self: *Persistence, a: M.Agg) void {
        if (self.failed) return;
        self.pending[self.len] = a;
        self.len += 1;
        if (self.len == self.pending.len) self.flush();
    }
    pub fn flush(self: *Persistence) void {
        if (self.failed) {
            self.len = 0;
            return;
        }
        var newest = self.last_persisted_sample_ms;
        const before = self.bytes_written;
        for (self.pending[0..self.len]) |a| {
            const item_before = self.bytes_written;
            self.append(a) catch {
                self.failed = true;
                break;
            };
            if (self.bytes_written > item_before) newest = @max(newest orelse 0, a.ts_wall_ms);
        }
        self.len = 0;
        if (self.file_fd >= 0) sys.sync(self.file_fd) catch {
            self.failed = true;
        };
        if (!self.failed and self.bytes_written > before) {
            self.last_persisted_sample_ms = newest;
            self.last_sync_ms = sys.wallMs();
        }
    }
    pub fn deinit(self: *Persistence) void {
        self.flush();
        if (self.file_fd >= 0) sys.close(self.file_fd);
        if (self.lock_fd >= 0) sys.close(self.lock_fd);
    }
    fn append(self: *Persistence, a: M.Agg) !void {
        const day = a.ts_wall_ms / day_ms;
        const today = sys.wallMs() / day_ms;
        if (day < today -| 6 or day > today) return;
        if (self.last_cleanup_day != day) self.cleanup(sys.wallMs() / day_ms);
        if (self.file_day != day or self.file_fd < 0) try self.openDay(day);
        if (self.offset >= header_size + max_records * record_size) return error.DailyLimit;
        try sys.pwriteAll(self.file_fd, &encode(a), self.offset);
        self.offset += record_size;
        self.bytes_written += record_size;
    }
    fn openDay(self: *Persistence, day: u64) !void {
        if (self.file_fd >= 0) {
            try sys.sync(self.file_fd);
            sys.close(self.file_fd);
            self.file_fd = -1;
        }
        var pbuf: [1024]u8 = undefined;
        const fd = try sys.openWrite(try self.path(&pbuf, day));
        errdefer sys.close(fd);
        var h: [header_size]u8 = undefined;
        const n = try sys.pread(fd, &h, 0);
        if (n == 0) {
            try sys.pwriteAll(fd, &header(day), 0);
        } else if (n != header_size or !std.mem.eql(u8, &h, &header(day))) return error.UnknownSchema;
        var bytes: [record_size]u8 = undefined;
        var offset: u64 = header_size;
        for (0..max_records) |_| {
            const got = try sys.pread(fd, &bytes, @intCast(offset));
            if (got == 0) break;
            if (got != record_size or decode(&bytes) == null) {
                try sys.truncate(fd, offset);
                break;
            }
            offset += record_size;
        }
        self.file_fd = fd;
        self.file_day = day;
        self.offset = offset;
    }
    fn cleanup(self: *Persistence, today: u64) void {
        var pbuf: [1024]u8 = undefined;
        const dirpath = std.fmt.bufPrintZ(&pbuf, "{s}", .{self.directory}) catch return;
        var d = sys.DirIter.open(dirpath) catch return;
        defer d.deinit();
        while (d.next()) |name| {
            if (!std.mem.endsWith(u8, name, ".dscp")) continue;
            const day = std.fmt.parseInt(u64, name[0 .. name.len - 5], 10) catch continue;
            if (day >= today -| 6 and day <= today) continue;
            const file = std.fmt.bufPrintZ(&pbuf, "{s}/{s}", .{ self.directory, name }) catch continue;
            sys.unlink(file) catch {
                self.failed = true;
            };
        }
        self.last_cleanup_day = today;
    }
};
test "record is portable and detects corruption" {
    const a = M.Agg{ .ts_wall_ms = 1234567, .count = 1, .available = M.bit(.battery_rate_mw), .values = @splat(-100) };
    var b = encode(a);
    const out = decode(&b).?;
    try std.testing.expectEqual(a.ts_wall_ms, out.ts_wall_ms);
    try std.testing.expectEqual(@as(i32, -100), out.values[0]);
    b[12] ^= 1;
    try std.testing.expect(decode(&b) == null);
}
