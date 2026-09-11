const std = @import("std");
const src = @import("source.zig");
const parsers = @import("parsers.zig");
const M = @import("model.zig");
const z = @import("device.zig").z;
pub const IoStats = struct {
    disk: src.Value,
    network: src.Value,
    devices: [64][64]u8 = @splat(@splat(0)),
    device_count: usize = 0,
    previous_disks: [2]?u64 = @splat(null),
    previous_count: usize = 0,
    previous_net: [4]?u64 = @splat(null),
    interface_name: [16]u8 = @splat(0),
    previous_us: u64 = 0,
    pub fn init() IoStats {
        var self = IoStats{ .disk = src.Value.init("/proc/diskstats"), .network = src.Value.init("/proc/net/dev") };
        var dir = src.dir("/sys/class/block") catch return self;
        defer dir.deinit();
        while (dir.next()) |entry| {
            if (self.device_count == self.devices.len or entry.len >= 64) continue;
            var buf: [512]u8 = undefined;
            const partition = src.Value.init(src.join(&buf, "/sys/class/block/{s}/partition", .{entry}) orelse continue);
            if (partition.fd >= 0) {
                var p = partition;
                p.close();
                continue;
            }
            var device = src.dir(src.join(&buf, "/sys/class/block/{s}/device", .{entry}) orelse continue) catch continue;
            device.deinit(); // excludes virtual block stacks; counts physical devices once
            @memcpy(self.devices[self.device_count][0..entry.len], entry);
            self.device_count += 1;
        }
        return self;
    }
    pub fn deinit(self: *IoStats) void {
        self.disk.close();
        self.network.close();
    }
    pub fn sample(self: *IoStats, out: *M.Sample, interface: ?[]const u8, now_us: u64) void {
        const elapsed = now_us -| self.previous_us;
        self.previous_us = now_us;
        self.diskSample(out, elapsed);
        self.netSample(out, interface, elapsed);
    }
    fn diskSample(self: *IoStats, s: *M.Sample, elapsed: u64) void {
        var buf: [32768]u8 = undefined;
        var totals: [2]u64 = @splat(0);
        var count: usize = 0;
        var lines = std.mem.splitScalar(u8, self.disk.read(&buf) orelse "", '\n');
        while (lines.next()) |line| {
            var words = std.mem.tokenizeAny(u8, line, " \t");
            _ = words.next();
            _ = words.next();
            const name = words.next() orelse continue;
            var known = false;
            for (self.devices[0..self.device_count]) |entry| if (std.mem.eql(u8, z(&entry), name)) {
                known = true;
                break;
            };
            if (!known) continue;
            var values: [7]u64 = undefined;
            var valid = true;
            for (&values) |*v| {
                v.* = std.fmt.parseInt(u64, words.next() orelse {
                    valid = false;
                    break;
                }, 10) catch {
                    valid = false;
                    break;
                };
            }
            if (!valid) continue;
            totals[0] +|= values[2];
            totals[1] +|= values[6];
            count += 1;
        }
        if (count == 0 or count != self.previous_count) self.previous_disks = @splat(null);
        for ([_]M.Metric{ .disk_read_kbps, .disk_write_kbps }, 0..) |metric, i| {
            // diskstats sectors are 512 bytes, irrespective of physical sector size.
            if (parsers.rate(self.previous_disks[i], if (count > 0) totals[i] else null, elapsed, 500000, std.math.maxInt(i32))) |v| s.set(metric, v);
            self.previous_disks[i] = if (count > 0) totals[i] else null;
        }
        self.previous_count = count;
    }
    fn netSample(self: *IoStats, s: *M.Sample, interface: ?[]const u8, elapsed: u64) void {
        const name = interface orelse {
            self.previous_net = @splat(null);
            return;
        };
        if (!std.mem.eql(u8, name, z(&self.interface_name))) {
            @memset(&self.interface_name, 0);
            const n = @min(name.len, self.interface_name.len - 1);
            @memcpy(self.interface_name[0..n], name[0..n]);
            self.previous_net = @splat(null);
        }
        var buf: [16384]u8 = undefined;
        var lines = std.mem.splitScalar(u8, self.network.read(&buf) orelse "", '\n');
        while (lines.next()) |line| {
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            if (!std.mem.eql(u8, std.mem.trim(u8, line[0..colon], " \t"), name)) continue;
            var words = std.mem.tokenizeAny(u8, line[colon + 1 ..], " \t");
            var values: [16]u64 = undefined;
            for (&values) |*v| v.* = std.fmt.parseInt(u64, words.next() orelse return, 10) catch return;
            const counters = [_]u64{ values[0], values[8], values[2], values[10] };
            for ([_]M.Metric{ .net_rx_kbps, .net_tx_kbps, .net_rx_errors_delta, .net_tx_errors_delta }, 0..) |metric, i| {
                if (i < 2) {
                    // Divide by 1024 after the microseconds-to-seconds conversion.
                    if (parsers.rate(self.previous_net[i], counters[i], elapsed, 1000000, std.math.maxInt(u32))) |bytes| s.set(metric, @divTrunc(bytes, 1024));
                } else if (self.previous_net[i]) |previous| {
                    if (counters[i] >= previous) s.set(metric, @intCast(@min(counters[i] - previous, std.math.maxInt(i32))));
                }
                self.previous_net[i] = counters[i];
            }
            return;
        }
        self.previous_net = @splat(null);
    }
};
