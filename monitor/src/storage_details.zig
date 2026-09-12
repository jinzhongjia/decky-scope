//! Bounded, redacted mounted-filesystem details for the QAM information view.
//!
//! Capacity is `statfs` capacity of each mounted filesystem, not physical SSD
//! capacity and not a sum of disks, partitions, or btrfs subvolumes.
const std = @import("std");
const linux = std.os.linux;
const src = @import("source.zig");
const sys = @import("sys.zig");
const proto = @import("protocol.zig");

const max_volumes = 12;
const max_mountinfo = 32 * 1024;

const Kind = enum { system, home, removable };

const Capacity = struct {
    total: ?u64 = null,
    available: ?u64 = null,
};

const Volume = struct {
    kind: Kind,
    major: u32,
    minor: u32,
    filesystem: []const u8,
    capacity: Capacity,
};

const ParsedMount = struct {
    major: u32,
    minor: u32,
    point: []const u8,
    filesystem: []const u8,
};

// Zig 0.16 exposes SYS.statfs through raw linux.syscall2, but has no typed
// statfs result. This is the 120-byte Linux x86_64 UAPI layout; only the
// documented block fields below are read. The monitor target is x86_64 Linux.
const LinuxStatfs = extern struct {
    f_type: i64,
    f_bsize: i64,
    f_blocks: u64,
    f_bfree: u64,
    f_bavail: u64,
    f_files: u64,
    f_ffree: u64,
    f_fsid: [2]i32,
    f_namelen: i64,
    f_frsize: i64,
    f_flags: i64,
    f_spare: [4]i64,
};

comptime {
    if (@sizeOf(LinuxStatfs) != 120) @compileError("unexpected Linux x86_64 statfs ABI");
}

/// Emit redacted filesystem types and mounted capacities. Device names, labels,
/// and mount paths are deliberately never serialized.
pub fn write(w: *std.Io.Writer) !void {
    var input: [max_mountinfo]u8 = undefined;
    var volumes: [max_volumes]Volume = undefined;
    var count: usize = 0;
    var truncated = false;

    if (readMountinfo(&input, &truncated)) |text| {
        collect(text, &volumes, &count, &truncated);
    }

    const removable_present = removableDevicePresent() or hasMountedRemovable(volumes[0..count]);
    try w.writeAll("{\"filesystems\":[");
    for (volumes[0..count], 0..) |volume, i| {
        if (i != 0) try w.writeByte(',');
        try w.writeAll("{\"kind\":");
        try proto.string(w, @tagName(volume.kind));
        try w.writeAll(",\"filesystem\":");
        try proto.string(w, volume.filesystem);
        try w.writeAll(",\"mounted\":true,\"total_bytes\":");
        try numberOrNull(w, volume.capacity.total);
        try w.writeAll(",\"available_bytes\":");
        try numberOrNull(w, volume.capacity.available);
        try w.writeByte('}');
    }
    try w.writeAll("],\"removable_present\":");
    try w.writeAll(if (removable_present) "true" else "false");
    try w.writeAll(",\"truncated\":");
    try w.writeAll(if (truncated) "true" else "false");
    try w.writeByte('}');
}

fn numberOrNull(w: *std.Io.Writer, value: ?u64) !void {
    if (value) |number| {
        try w.print("{d}", .{number});
    } else {
        try w.writeAll("null");
    }
}

fn readMountinfo(buf: []u8, truncated: *bool) ?[]const u8 {
    // src.open prefixes source.root, so a fixture can never fall back to host
    // /proc when it omits mountinfo.
    const fd = src.open("/proc/self/mountinfo") catch return null;
    defer sys.close(fd);
    const n = sys.pread(fd, buf, 0) catch return null;
    if (n == buf.len) truncated.* = true;
    return buf[0..n];
}

fn collect(text: []const u8, volumes: []Volume, count: *usize, truncated: *bool) void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        var point_buf: [512]u8 = undefined;
        const mount = parseMountLine(line, &point_buf) orelse continue;
        const kind = classify(mount.point, mount.filesystem) orelse continue;
        addVolume(volumes, count, truncated, kind, mount.major, mount.minor, mount.filesystem, capacityAt(mount.point));
    }
}

fn parseMountLine(line: []const u8, point_buf: []u8) ?ParsedMount {
    var fields = std.mem.tokenizeAny(u8, line, " \t");
    _ = fields.next() orelse return null; // mount ID
    _ = fields.next() orelse return null; // parent ID
    const major_minor = fields.next() orelse return null;
    _ = fields.next() orelse return null; // mount root
    const encoded_point = fields.next() orelse return null;

    const colon = std.mem.indexOfScalar(u8, major_minor, ':') orelse return null;
    const major = std.fmt.parseInt(u32, major_minor[0..colon], 10) catch return null;
    const minor = std.fmt.parseInt(u32, major_minor[colon + 1 ..], 10) catch return null;
    const point = decodeMountinfo(encoded_point, point_buf) orelse return null;

    while (fields.next()) |field| {
        if (std.mem.eql(u8, field, "-")) break;
    } else return null;
    const filesystem = fields.next() orelse return null;
    if (filesystem.len == 0 or filesystem.len > 32) return null;
    return .{ .major = major, .minor = minor, .point = point, .filesystem = filesystem };
}

fn decodeMountinfo(encoded: []const u8, out: []u8) ?[]const u8 {
    var input_index: usize = 0;
    var output_index: usize = 0;
    while (input_index < encoded.len) {
        var byte = encoded[input_index];
        if (byte == '\\' and input_index + 3 < encoded.len) {
            const a = encoded[input_index + 1];
            const b = encoded[input_index + 2];
            const c = encoded[input_index + 3];
            if (a >= '0' and a <= '3' and b >= '0' and b <= '7' and c >= '0' and c <= '7') {
                byte = (a - '0') * 64 + (b - '0') * 8 + (c - '0');
                input_index += 4;
            } else {
                input_index += 1;
            }
        } else {
            input_index += 1;
        }
        if (byte == 0 or output_index == out.len) return null;
        out[output_index] = byte;
        output_index += 1;
    }
    return out[0..output_index];
}

fn classify(point: []const u8, filesystem: []const u8) ?Kind {
    if (!isLocalFilesystem(filesystem)) return null;
    if (std.mem.eql(u8, point, "/")) return .system;
    if (std.mem.eql(u8, point, "/home") or std.mem.eql(u8, point, "/var/home")) return .home;
    if (std.mem.startsWith(u8, point, "/run/media/") and point.len > "/run/media/".len) return .removable;
    return null;
}

fn isLocalFilesystem(filesystem: []const u8) bool {
    const local = [_][]const u8{
        "btrfs", "bcachefs", "ext2", "ext3",  "ext4", "xfs",     "f2fs",    "jfs",   "nilfs2",   "reiserfs",
        "vfat",  "exfat",    "ntfs", "ntfs3", "udf",  "iso9660", "hfsplus", "erofs", "squashfs", "zfs",
    };
    for (local) |known| if (std.mem.eql(u8, filesystem, known)) return true;
    return false; // excludes network, FUSE, and pseudo filesystems before statfs.
}

fn addVolume(
    volumes: []Volume,
    count: *usize,
    truncated: *bool,
    kind: Kind,
    major: u32,
    minor: u32,
    filesystem: []const u8,
    capacity: Capacity,
) void {
    if (!insertVolume(volumes, count, kind, major, minor, filesystem, capacity)) truncated.* = true;
}

fn insertVolume(
    volumes: []Volume,
    count: *usize,
    kind: Kind,
    major: u32,
    minor: u32,
    filesystem: []const u8,
    capacity: Capacity,
) bool {
    for (volumes[0..count.*]) |*existing| {
        if (existing.major != major or existing.minor != minor or !std.mem.eql(u8, existing.filesystem, filesystem)) continue;
        // A shared root/home filesystem is reported only once, as home.
        if (kindRank(kind) > kindRank(existing.kind)) {
            existing.kind = kind;
            existing.capacity = capacity;
        }
        return true;
    }
    if (count.* == volumes.len) return false;
    volumes[count.*] = .{
        .kind = kind,
        .major = major,
        .minor = minor,
        .filesystem = filesystem,
        .capacity = capacity,
    };
    count.* += 1;
    return true;
}

fn kindRank(kind: Kind) u8 {
    return switch (kind) {
        .system => 0,
        .removable => 1,
        .home => 2,
    };
}

fn capacityAt(mount_point: []const u8) Capacity {
    // src.path prefixes source.root for both production and fixtures; no path
    // is retried without that prefix after a fixture statfs failure.
    var path_buf: [1024]u8 = undefined;
    const path = src.path(&path_buf, mount_point) orelse return .{};
    var stat: LinuxStatfs = undefined;
    const rc = linux.syscall2(.statfs, @intCast(@intFromPtr(path.ptr)), @intCast(@intFromPtr(&stat)));
    if (linux.errno(@intCast(rc)) != .SUCCESS) return .{};

    const unit: i64 = if (stat.f_frsize > 0) stat.f_frsize else stat.f_bsize;
    if (unit <= 0) return .{};
    const bytes_per_block: u64 = @intCast(unit);
    return .{
        .total = std.math.mul(u64, stat.f_blocks, bytes_per_block) catch null,
        .available = std.math.mul(u64, stat.f_bavail, bytes_per_block) catch null,
    };
}

fn removableDevicePresent() bool {
    var block_dir = src.dir("/sys/block") catch return false;
    defer block_dir.deinit();
    while (block_dir.next()) |entry| {
        if (!std.mem.startsWith(u8, entry, "mmcblk")) continue;
        var path_buf: [256]u8 = undefined;
        const suffix = src.join(&path_buf, "/sys/block/{s}/removable", .{entry}) orelse continue;
        var value_buf: [16]u8 = undefined;
        if (src.text(suffix, &value_buf)) |value| if (std.mem.eql(u8, value, "1")) {
            return true;
        };
        // Some SD hosts do not set the generic removable bit; MMC is not SD.
        const kind_path = src.join(&path_buf, "/sys/block/{s}/device/type", .{entry}) orelse continue;
        if (src.text(kind_path, &value_buf)) |kind| if (std.mem.eql(u8, kind, "SD")) {
            return true;
        };
    }
    return false;
}

fn hasMountedRemovable(volumes: []const Volume) bool {
    for (volumes) |volume| if (volume.kind == .removable) return true;
    return false;
}

test "mountinfo parser decodes escaped spaces" {
    var point: [128]u8 = undefined;
    const mount = parseMountLine(
        "37 22 179:1 / /run/media/Card\\040One rw,nosuid,nodev - exfat /dev/mmcblk0p1 rw",
        &point,
    ).?;
    try std.testing.expectEqual(@as(u32, 179), mount.major);
    try std.testing.expectEqualStrings("/run/media/Card One", mount.point);
    try std.testing.expectEqualStrings("exfat", mount.filesystem);
    try std.testing.expectEqual(Kind.removable, classify(mount.point, mount.filesystem).?);
}

test "deduplication prioritizes home over shared system filesystem" {
    var volumes: [2]Volume = undefined;
    var count: usize = 0;
    const capacity = Capacity{ .total = 10, .available = 4 };
    try std.testing.expect(insertVolume(&volumes, &count, .system, 259, 2, "btrfs", capacity));
    try std.testing.expect(insertVolume(&volumes, &count, .home, 259, 2, "btrfs", capacity));
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(Kind.home, volumes[0].kind);
}

test "pseudo and remote filesystem types are excluded" {
    try std.testing.expect(classify("/", "proc") == null);
    try std.testing.expect(classify("/", "tmpfs") == null);
    try std.testing.expect(classify("/", "fuse.sshfs") == null);
    try std.testing.expect(classify("/", "nfs") == null);
}

test "volume cap reports truncation" {
    var volumes: [2]Volume = undefined;
    var count: usize = 0;
    var truncated = false;
    const capacity = Capacity{};
    addVolume(&volumes, &count, &truncated, .system, 8, 1, "ext4", capacity);
    addVolume(&volumes, &count, &truncated, .removable, 8, 2, "exfat", capacity);
    addVolume(&volumes, &count, &truncated, .removable, 8, 3, "vfat", capacity);
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expect(truncated);
}

test "classification is stable for supported mount locations" {
    try std.testing.expectEqual(Kind.system, classify("/", "btrfs").?);
    try std.testing.expectEqual(Kind.home, classify("/home", "ext4").?);
    try std.testing.expectEqual(Kind.home, classify("/var/home", "btrfs").?);
    try std.testing.expectEqual(Kind.removable, classify("/run/media/deck/card", "exfat").?);
    try std.testing.expect(classify("/run/media", "exfat") == null);
    try std.testing.expect(classify("/mnt/card", "exfat") == null);
}
