const std = @import("std");
const sys = @import("sys.zig");
const src = @import("source.zig");
const p = @import("parsers.zig");
const M = @import("model.zig");
const Sensors = @import("sensors.zig").Sensors;
pub const Sampler = struct {
    stat: src.Value,
    mem: src.Value,
    pressure: [3]src.Value,
    sensors: Sensors,
    prev_cpu: ?p.Cpu = null,
    prev_threads: [256]?p.Cpu = @splat(null),
    threads: [256]?u16 = @splat(null),
    online: u32 = 0,
    topology_truncated: bool = false,
    prev_psi: [5]?u64 = @splat(null),
    prev_us: u64 = 0,
    buf: [65536]u8 = undefined,
    pub fn init() Sampler {
        return .{ .stat = src.Value.init("/proc/stat"), .mem = src.Value.init("/proc/meminfo"), .pressure = .{ src.Value.init("/proc/pressure/cpu"), src.Value.init("/proc/pressure/memory"), src.Value.init("/proc/pressure/io") }, .sensors = Sensors.init() };
    }
    pub fn deinit(self: *Sampler) void {
        self.stat.close();
        self.mem.close();
        for (&self.pressure) |*v| v.close();
        self.sensors.deinit();
    }
    pub fn reset(self: *Sampler) void {
        self.deinit();
        self.* = init();
    }
    pub fn sample(self: *Sampler) M.Sample {
        const now = sys.nowUs();
        const elapsed = now -| self.prev_us;
        var s = M.Sample{ .ts_wall_ms = sys.wallMs() };
        self.cpu(&s);
        if (self.mem.read(&self.buf)) |text| p.meminfo(text, &s);
        const fields = [_]M.Metric{ .psi_cpu_some_x100, .psi_mem_some_x100, .psi_mem_full_x100, .psi_io_some_x100, .psi_io_full_x100 };
        var j: usize = 0;
        for (self.pressure, 0..) |file, i| {
            const text = file.read(&self.buf) orelse "";
            for (0..(if (i == 0) @as(usize, 1) else 2)) |k| {
                const current = p.pressureTotal(text, if (k == 0) "some" else "full");
                if (p.rate(self.prev_psi[j], current, elapsed, 10000, 10000)) |value| s.set(fields[j], value);
                self.prev_psi[j] = current;
                j += 1;
            }
        }
        self.sensors.sample(&s, now);
        self.prev_us = now;
        return s;
    }
    fn cpu(self: *Sampler, s: *M.Sample) void {
        const text = self.stat.read(&self.buf) orelse {
            self.prev_cpu = null;
            self.prev_threads = @splat(null);
            self.threads = @splat(null);
            return;
        };
        var lines = std.mem.splitScalar(u8, text, '\n');
        var seen: [256]bool = @splat(false);
        self.online = 0;
        self.topology_truncated = false;
        self.threads = @splat(null);
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "cpu ")) {
                const cur = p.cpu(line) orelse {
                    self.prev_cpu = null;
                    continue;
                };
                if (p.usage(self.prev_cpu, cur)) |v| s.set(.cpu_pct_x10, v);
                self.prev_cpu = cur;
            } else if (std.mem.startsWith(u8, line, "cpu")) {
                const end = std.mem.indexOfAny(u8, line, " \t") orelse continue;
                const id = std.fmt.parseInt(usize, line[3..end], 10) catch continue;
                self.online += 1;
                if (id >= seen.len) {
                    self.topology_truncated = true;
                    continue;
                }
                seen[id] = true;
                const cur = p.cpu(line) orelse {
                    self.prev_threads[id] = null;
                    continue;
                };
                self.threads[id] = p.usage(self.prev_threads[id], cur);
                self.prev_threads[id] = cur;
            }
        }
        for (seen, 0..) |yes, id| if (!yes) {
            self.prev_threads[id] = null;
        };
    }
};
