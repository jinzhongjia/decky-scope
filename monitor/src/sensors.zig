const std = @import("std");
const src = @import("source.zig");
const M = @import("model.zig");
const Value = src.Value;
pub const Sensors = struct {
    values: [M.metric_count]Value = @splat(.{}),
    divisors: [M.metric_count]i64 = @splat(1),
    cpufreq: [256]Value = @splat(.{}),
    battery_status: Value = .{},
    cpu_source: [64]u8 = @splat(0),
    battery_source: [64]u8 = @splat(0),
    gpu_source: [64]u8 = @splat(0),
    pub fn init() Sensors {
        var self = Sensors{};
        var buf: [512]u8 = undefined;
        var cpus = src.dir("/sys/devices/system/cpu") catch null;
        if (cpus) |*d| {
            defer d.deinit();
            while (d.next()) |entry| {
                if (!std.mem.startsWith(u8, entry, "cpu")) continue;
                const id = std.fmt.parseInt(usize, entry[3..], 10) catch continue;
                if (id >= self.cpufreq.len) continue;
                self.cpufreq[id] = Value.init(src.join(&buf, "/sys/devices/system/cpu/{s}/cpufreq/scaling_cur_freq", .{entry}) orelse continue);
            }
        }
        self.hwmon();
        self.gpu();
        self.battery();
        return self;
    }
    pub fn deinit(self: *Sensors) void {
        for (&self.values) |*v| v.close();
        for (&self.cpufreq) |*v| v.close();
        self.battery_status.close();
    }
    fn claim(self: *Sensors, m: M.Metric, base: []const u8, leaf: []const u8, divisor: i64) bool {
        const id = @intFromEnum(m);
        if (self.values[id].fd >= 0) return false;
        var buf: [512]u8 = undefined;
        self.values[id] = Value.init(src.join(&buf, "{s}/{s}", .{ base, leaf }) orelse return false);
        self.divisors[id] = divisor;
        return self.values[id].fd >= 0;
    }
    fn hwmon(self: *Sensors) void {
        var boardbuf: [64]u8 = undefined;
        const board = src.text("/sys/class/dmi/id/board_name", &boardbuf) orelse "";
        const deck = std.mem.eql(u8, board, "Galileo") or std.mem.eql(u8, board, "Jupiter");
        // Two passes: preferred package sensor, then clearly-labelled ACPI fallback.
        for (0..2) |pass| {
            var d = src.dir("/sys/class/hwmon") catch return;
            defer d.deinit();
            while (d.next()) |entry| {
                var basebuf: [256]u8 = undefined;
                var pathbuf: [512]u8 = undefined;
                var namebuf: [64]u8 = undefined;
                const base = src.join(&basebuf, "/sys/class/hwmon/{s}", .{entry}) orelse continue;
                const name = src.text(src.join(&pathbuf, "{s}/name", .{base}) orelse continue, &namebuf) orelse continue;
                const preferred = if (deck) std.mem.eql(u8, name, "acpitz") else std.mem.eql(u8, name, "k10temp") or std.mem.eql(u8, name, "coretemp") or std.mem.eql(u8, name, "zenpower");
                if ((pass == 0 and preferred) or (pass == 1 and std.mem.eql(u8, name, "acpitz"))) {
                    if (self.claim(.cpu_temp_mc, base, "temp1_input", 1)) copy(&self.cpu_source, name);
                }
                if (std.mem.eql(u8, name, "nvme")) _ = self.claim(.nvme_temp_mc, base, "temp1_input", 1);
                if (std.mem.eql(u8, name, "steamdeck_hwmon") or std.mem.eql(u8, name, "jupiter"))
                    _ = self.claim(.fan_rpm, base, "fan1_input", 1);
            }
        }
    }
    fn gpu(self: *Sensors) void {
        var d = src.dir("/sys/class/drm") catch return;
        defer d.deinit();
        while (d.next()) |entry| {
            if (!std.mem.startsWith(u8, entry, "card")) continue;
            _ = std.fmt.parseInt(u32, entry[4..], 10) catch continue;
            var buf: [256]u8 = undefined;
            const base = src.join(&buf, "/sys/class/drm/{s}/device", .{entry}) orelse continue;
            if (self.claim(.gpu_pct, base, "gpu_busy_percent", 1)) {
                copy(&self.gpu_source, entry);
                self.gpuHwmon(base);
                break;
            }
        }
    }
    fn gpuHwmon(self: *Sensors, device: []const u8) void {
        var pathbuf: [512]u8 = undefined;
        const path = src.join(&pathbuf, "{s}/hwmon", .{device}) orelse return;
        var d = src.dir(path) catch return;
        defer d.deinit();
        var boardbuf: [64]u8 = undefined;
        const board = src.text("/sys/class/dmi/id/board_name", &boardbuf) orelse "";
        const deck = std.mem.eql(u8, board, "Galileo") or std.mem.eql(u8, board, "Jupiter");
        while (d.next()) |entry| {
            var basebuf: [512]u8 = undefined;
            const base = src.join(&basebuf, "{s}/hwmon/{s}", .{ device, entry }) orelse continue;
            var namebuf: [64]u8 = undefined;
            const name = src.text(src.join(&pathbuf, "{s}/name", .{base}) orelse continue, &namebuf) orelse continue;
            if (!std.mem.eql(u8, name, "amdgpu")) continue;
            _ = self.claim(.gpu_temp_mc, base, "temp1_input", 1);
            _ = self.claim(.gpu_mhz, base, "freq1_input", 1000000);
            if (deck) _ = self.claim(.apu_power_mw, base, "power1_average", 1000);
            break;
        }
    }
    fn battery(self: *Sensors) void {
        var d = src.dir("/sys/class/power_supply") catch return;
        defer d.deinit();
        while (d.next()) |entry| {
            var basebuf: [256]u8 = undefined;
            var pathbuf: [512]u8 = undefined;
            var txt: [64]u8 = undefined;
            const base = src.join(&basebuf, "/sys/class/power_supply/{s}", .{entry}) orelse continue;
            const kind = src.text(src.join(&pathbuf, "{s}/type", .{base}) orelse continue, &txt) orelse continue;
            if (!std.mem.eql(u8, kind, "Battery")) continue;
            const present = src.text(src.join(&pathbuf, "{s}/present", .{base}) orelse continue, &txt);
            if (present != null and std.mem.eql(u8, present.?, "0")) continue;
            if (self.claim(.battery_pct, base, "capacity", 1)) {
                _ = self.claim(.battery_rate_mw, base, "power_now", 1000);
                self.battery_status = Value.init(src.join(&pathbuf, "{s}/status", .{base}) orelse continue);
                copy(&self.battery_source, entry);
                break;
            }
        }
    }
    pub fn sample(self: *const Sensors, s: *M.Sample) void {
        for (self.values, 0..) |v, i| if (v.int()) |value| {
            const metric: M.Metric = @enumFromInt(i);
            if (metric == .battery_rate_mw) continue;
            if ((metric == .battery_pct or metric == .gpu_pct) and (value < 0 or value > 100)) continue;
            s.set(metric, @divTrunc(value, self.divisors[i]));
        };
        var sum: i64 = 0;
        var count: i64 = 0;
        for (self.cpufreq) |v| if (v.int()) |khz| {
            if (khz > 0 and khz < 100000000) {
                sum += khz;
                count += 1;
            }
        };
        if (count > 0) s.set(.cpu_mhz, @divTrunc(sum, count * 1000));
        var buf: [32]u8 = undefined;
        if (self.battery_status.read(&buf)) |state| {
            if (self.values[@intFromEnum(M.Metric.battery_rate_mw)].int()) |uw| {
                if (uw < 0) return;
                if (std.mem.eql(u8, state, "Discharging")) s.set(.battery_rate_mw, @divTrunc(uw, 1000));
                if (std.mem.eql(u8, state, "Charging")) s.set(.battery_rate_mw, -@divTrunc(uw, 1000));
                if (std.mem.eql(u8, state, "Full") or std.mem.eql(u8, state, "Not charging")) s.set(.battery_rate_mw, 0);
            }
        }
    }
};
fn copy(dest: []u8, value: []const u8) void {
    @memset(dest, 0);
    @memcpy(dest[0..@min(dest.len - 1, value.len)], value[0..@min(dest.len - 1, value.len)]);
}
