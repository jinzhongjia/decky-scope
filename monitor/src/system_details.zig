const std = @import("std");
const src = @import("source.zig");
const sys = @import("sys.zig");

/// The maximum number of zram block devices inspected in one manual snapshot.
const max_zram_devices = 64;

const Clocks = struct {
    boot_elapsed_ms: ?u64 = null,
    awake_ms: ?u64 = null,
    suspended_ms: ?u64 = null,
};

const Memory = struct {
    available_kib: ?u64 = null,
    cached_kib: ?u64 = null,
    reclaimable_kib: ?u64 = null,
    dirty_kib: ?u64 = null,
    writeback_kib: ?u64 = null,
    swap_total_kib: ?u64 = null,
    swap_free_kib: ?u64 = null,
};

const Zram = struct {
    devices: u8 = 0,
    original_bytes: ?u64 = null,
    compressed_bytes: ?u64 = null,
    memory_used_bytes: ?u64 = null,
};

const Sums = struct {
    values: [3]?u64 = .{ null, null, null },
    overflowed: [3]bool = .{ false, false, false },

    fn add(self: *Sums, index: usize, value: ?u64) void {
        const next = value orelse return;
        if (self.overflowed[index]) return;
        if (self.values[index]) |current| {
            self.values[index] = std.math.add(u64, current, next) catch {
                self.values[index] = null;
                self.overflowed[index] = true;
                return;
            };
        } else self.values[index] = next;
    }
};

/// Writes one bounded manual snapshot.  Reads are rooted at src.root, so a
/// non-empty fixture root is never supplemented with host proc/sysfs data.
pub fn write(w: *std.Io.Writer) !void {
    const clocks = readClocks();

    var load_buf: [256]u8 = undefined;
    const load = if (src.text("/proc/loadavg", &load_buf)) |text| loadavg(text) else [3]?u64{ null, null, null };

    var mem_buf: [16384]u8 = undefined;
    const memory = if (src.text("/proc/meminfo", &mem_buf)) |text| meminfo(text) else Memory{};
    const zram = readZram();

    var zswap_buf: [32]u8 = undefined;
    const zswap_enabled = if (src.text("/sys/module/zswap/parameters/enabled", &zswap_buf)) |text| boolValue(text) else null;

    try w.writeAll("{\"boot_elapsed_ms\":");
    try nullableU64(w, clocks.boot_elapsed_ms);
    try w.writeAll(",\"awake_ms\":");
    try nullableU64(w, clocks.awake_ms);
    try w.writeAll(",\"suspended_ms\":");
    try nullableU64(w, clocks.suspended_ms);

    try w.writeAll(",\"load_x1000\":[");
    for (load, 0..) |value, i| {
        if (i != 0) try w.writeByte(',');
        try nullableU64(w, value);
    }
    try w.writeAll("],\"memory\":{");
    try memoryJson(w, memory);
    try w.writeAll("},\"zram\":{");
    try zramJson(w, zram);
    try w.writeAll("},\"zswap_enabled\":");
    try nullableBool(w, zswap_enabled);
    try w.writeByte('}');
}

fn readClocks() Clocks {
    // Fixture mode deliberately has no timing fallback: this prevents a host
    // uptime leak when a fixture omits either optional clock file.
    if (src.root.len != 0) {
        var boot_buf: [64]u8 = undefined;
        var awake_buf: [64]u8 = undefined;
        const boot = if (src.text("/proc/deckscope_boot_ms", &boot_buf)) |text| counter(text) else null;
        const awake = if (src.text("/proc/deckscope_awake_ms", &awake_buf)) |text| counter(text) else null;
        return clockDetails(boot, awake);
    }
    const awake = sys.nowMs();
    return clockDetails(sys.bootMs(), awake);
}

fn clockDetails(boot: ?u64, awake: ?u64) Clocks {
    return .{
        .boot_elapsed_ms = boot,
        .awake_ms = awake,
        .suspended_ms = if (boot) |b| if (awake) |a| if (b >= a) b - a else null else null else null,
    };
}

/// Parses a non-negative counter without accepting signs or whitespace.
fn counter(text: []const u8) ?u64 {
    if (text.len == 0) return null;
    var value: u64 = 0;
    for (text) |char| {
        if (char < '0' or char > '9') return null;
        value = std.math.mul(u64, value, 10) catch return null;
        value = std.math.add(u64, value, char - '0') catch return null;
    }
    return value;
}

/// Parses a decimal load average exactly at the x1000 scale.  Extra decimal
/// places are accepted only when they are zero, avoiding silent rounding.
fn decimalX1000(text: []const u8) ?u64 {
    if (text.len == 0) return null;
    var pos: usize = 0;
    var whole: u64 = 0;
    while (pos < text.len and text[pos] != '.') : (pos += 1) {
        const char = text[pos];
        if (char < '0' or char > '9') return null;
        whole = std.math.mul(u64, whole, 10) catch return null;
        whole = std.math.add(u64, whole, char - '0') catch return null;
    }
    if (pos == 0) return null;

    var fraction: u64 = 0;
    var places: u8 = 0;
    if (pos < text.len) {
        pos += 1;
        if (pos == text.len) return null;
        while (pos < text.len) : (pos += 1) {
            const char = text[pos];
            if (char < '0' or char > '9') return null;
            if (places < 3) {
                fraction = fraction * 10 + (char - '0');
                places += 1;
            } else if (char != '0') return null;
        }
    }
    while (places < 3) : (places += 1) fraction *= 10;
    const scaled = std.math.mul(u64, whole, 1000) catch return null;
    return std.math.add(u64, scaled, fraction) catch null;
}

fn loadavg(text: []const u8) [3]?u64 {
    var result = [3]?u64{ null, null, null };
    var fields = std.mem.tokenizeAny(u8, text, " \t\r\n");
    for (&result) |*slot| slot.* = decimalX1000(fields.next() orelse continue);
    return result;
}

fn meminfo(text: []const u8) Memory {
    var result = Memory{};
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \t\r");
        const key = fields.next() orelse continue;
        const value = counter(fields.next() orelse continue) orelse continue;
        if (!std.mem.eql(u8, fields.next() orelse continue, "kB")) continue;

        if (std.mem.eql(u8, key, "MemAvailable:")) {
            result.available_kib = value;
        } else if (std.mem.eql(u8, key, "Cached:")) {
            result.cached_kib = value;
        } else if (std.mem.eql(u8, key, "SReclaimable:")) {
            result.reclaimable_kib = value;
        } else if (std.mem.eql(u8, key, "Dirty:")) {
            result.dirty_kib = value;
        } else if (std.mem.eql(u8, key, "Writeback:")) {
            result.writeback_kib = value;
        } else if (std.mem.eql(u8, key, "SwapTotal:")) {
            result.swap_total_kib = value;
        } else if (std.mem.eql(u8, key, "SwapFree:")) {
            result.swap_free_kib = value;
        }
    }
    return result;
}

fn readZram() Zram {
    var result = Zram{};
    var sums = Sums{};
    var complete = true;
    var directory = src.dir("/sys/block") catch return result;
    defer directory.deinit();

    while (directory.next()) |entry| {
        if (!zramName(entry)) continue;
        if (result.devices == max_zram_devices) {
            complete = false;
            break;
        }
        result.devices += 1;

        var path_buf: [512]u8 = undefined;
        var stat_buf: [256]u8 = undefined;
        const path = src.join(&path_buf, "/sys/block/{s}/mm_stat", .{entry}) orelse {
            complete = false;
            continue;
        };
        const text = src.text(path, &stat_buf) orelse {
            complete = false;
            continue;
        };
        const values = mmStat(text);
        for (values) |value| if (value == null) {
            complete = false;
        };
        inline for (0..3) |i| sums.add(i, values[i]);
    }
    if (!complete) return result;
    result.original_bytes = sums.values[0];
    result.compressed_bytes = sums.values[1];
    result.memory_used_bytes = sums.values[2];
    return result;
}

fn zramName(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "zram") or name.len == 4) return false;
    for (name[4..]) |char| if (char < '0' or char > '9') return false;
    return true;
}

/// Returns only mm_stat's documented first three byte counters.
fn mmStat(text: []const u8) [3]?u64 {
    var result = [3]?u64{ null, null, null };
    var fields = std.mem.tokenizeAny(u8, text, " \t\r\n");
    for (&result) |*slot| slot.* = counter(fields.next() orelse continue);
    return result;
}

fn boolValue(text: []const u8) ?bool {
    if (std.mem.eql(u8, text, "Y") or std.mem.eql(u8, text, "y") or std.mem.eql(u8, text, "1") or std.mem.eql(u8, text, "true")) return true;
    if (std.mem.eql(u8, text, "N") or std.mem.eql(u8, text, "n") or std.mem.eql(u8, text, "0") or std.mem.eql(u8, text, "false")) return false;
    return null;
}

fn nullableU64(w: *std.Io.Writer, value: ?u64) !void {
    if (value) |number| try w.print("{d}", .{number}) else try w.writeAll("null");
}

fn nullableBool(w: *std.Io.Writer, value: ?bool) !void {
    if (value) |enabled| try w.writeAll(if (enabled) "true" else "false") else try w.writeAll("null");
}

fn memoryJson(w: *std.Io.Writer, memory: Memory) !void {
    try w.writeAll("\"available_kib\":");
    try nullableU64(w, memory.available_kib);
    try w.writeAll(",\"cached_kib\":");
    try nullableU64(w, memory.cached_kib);
    try w.writeAll(",\"reclaimable_kib\":");
    try nullableU64(w, memory.reclaimable_kib);
    try w.writeAll(",\"dirty_kib\":");
    try nullableU64(w, memory.dirty_kib);
    try w.writeAll(",\"writeback_kib\":");
    try nullableU64(w, memory.writeback_kib);
    try w.writeAll(",\"swap_total_kib\":");
    try nullableU64(w, memory.swap_total_kib);
    try w.writeAll(",\"swap_free_kib\":");
    try nullableU64(w, memory.swap_free_kib);
}

fn zramJson(w: *std.Io.Writer, zram: Zram) !void {
    try w.print("\"devices\":{d},\"original_bytes\":", .{zram.devices});
    try nullableU64(w, zram.original_bytes);
    try w.writeAll(",\"compressed_bytes\":");
    try nullableU64(w, zram.compressed_bytes);
    try w.writeAll(",\"memory_used_bytes\":");
    try nullableU64(w, zram.memory_used_bytes);
}

test "load averages use exact fixed-point x1000 parsing" {
    const values = loadavg("0.01 2.5 12.0000 7/8 123");
    try std.testing.expectEqual(@as(?u64, 10), values[0]);
    try std.testing.expectEqual(@as(?u64, 2500), values[1]);
    try std.testing.expectEqual(@as(?u64, 12000), values[2]);
    try std.testing.expect(decimalX1000("1.2345") == null);
    try std.testing.expect(decimalX1000("-1.0") == null);
}

test "missing and invalid counters remain unavailable" {
    const memory = meminfo(
        "MemAvailable: -1 kB\n" ++
            "Cached: 12 MB\n" ++
            "Dirty: not-a-number kB\n" ++
            "SwapFree: 8 kB\n",
    );
    try std.testing.expect(memory.available_kib == null);
    try std.testing.expect(memory.cached_kib == null);
    try std.testing.expect(memory.dirty_kib == null);
    try std.testing.expectEqual(@as(?u64, 8), memory.swap_free_kib);
    const counters = mmStat("10 invalid 30");
    try std.testing.expectEqual(@as(?u64, 10), counters[0]);
    try std.testing.expect(counters[1] == null);
    try std.testing.expectEqual(@as(?u64, 30), counters[2]);
}

test "clock ordering prevents a negative suspended duration" {
    const ordered = clockDetails(4200, 1200);
    try std.testing.expectEqual(@as(?u64, 4200), ordered.boot_elapsed_ms);
    try std.testing.expectEqual(@as(?u64, 1200), ordered.awake_ms);
    try std.testing.expectEqual(@as(?u64, 3000), ordered.suspended_ms);
    const unordered = clockDetails(100, 101);
    try std.testing.expect(unordered.suspended_ms == null);
    try std.testing.expect(clockDetails(null, 10).suspended_ms == null);
}

test "zram counters aggregate bytes and preserve absent columns" {
    var sums = Sums{};
    const first = mmStat("1024 512 768 0 0");
    const second = mmStat("2048 1024 1536");
    const invalid = mmStat("bad 4 5");
    inline for (0..3) |i| {
        sums.add(i, first[i]);
        sums.add(i, second[i]);
        sums.add(i, invalid[i]);
    }
    try std.testing.expectEqual(@as(?u64, 3072), sums.values[0]);
    try std.testing.expectEqual(@as(?u64, 1540), sums.values[1]);
    try std.testing.expectEqual(@as(?u64, 2309), sums.values[2]);
    try std.testing.expect(zramName("zram0"));
    try std.testing.expect(!zramName("zram"));
    try std.testing.expect(!zramName("zram0p1"));
}

test "meminfo exposes kernel kB counters as KiB field values" {
    const memory = meminfo("MemAvailable: 4096 kB\nSReclaimable: 512 kB\nSwapTotal: 1024 kB\n");
    try std.testing.expectEqual(@as(?u64, 4096), memory.available_kib);
    try std.testing.expectEqual(@as(?u64, 512), memory.reclaimable_kib);
    try std.testing.expectEqual(@as(?u64, 1024), memory.swap_total_kib);
}

test "fixture root never falls back to host timing" {
    const previous_root = src.root;
    defer src.root = previous_root;
    src.root = "/deckscope_nonexistent_fixture";

    var bytes: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try write(&writer);
    try std.testing.expectEqualStrings(
        "{\"boot_elapsed_ms\":null,\"awake_ms\":null,\"suspended_ms\":null,\"load_x1000\":[null,null,null],\"memory\":{\"available_kib\":null,\"cached_kib\":null,\"reclaimable_kib\":null,\"dirty_kib\":null,\"writeback_kib\":null,\"swap_total_kib\":null,\"swap_free_kib\":null},\"zram\":{\"devices\":0,\"original_bytes\":null,\"compressed_bytes\":null,\"memory_used_bytes\":null},\"zswap_enabled\":null}",
        writer.buffered(),
    );
}
