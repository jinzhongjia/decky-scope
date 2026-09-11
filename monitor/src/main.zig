const std = @import("std");
const sys = @import("sys.zig");
const M = @import("model.zig");
const proto = @import("protocol.zig");
const Sampler = @import("sampler.zig").Sampler;
const Store = @import("store.zig").Store;
const Persistence = @import("persist.zig").Persistence;
const Device = @import("device.zig").Device;
const Transport = @import("transport.zig").Transport;
const IoStats = @import("io_stats.zig").IoStats;
const Netlink = @import("netlink.zig").Netlink;
var net: Netlink = .{};
const runtime = @import("runtime.zig");
pub const panic = runtime.panic;
pub const std_options = runtime.std_options;
pub const std_options_debug_threaded_io: ?*std.Io.Threaded = null;
var store: Store = .{};
var transport: Transport = .{};
var response: [proto.MAX_LINE]u8 = @splat(0);
var parse_memory: [32768]u8 = @splat(0);
const State = struct {
    interval_ms: u32 = 1000,
    live: bool = false,
    samples: u64 = 0,
    sample_total_us: u64 = 0,
    sample_max_us: u64 = 0,
    protocol_errors: u64 = 0,
    last: M.Sample = .{},
    last_sent: ?M.Sample = null,
    last_sent_ms: u64 = 0,
    started: u64 = 0,
    last_boot: u64 = 0,
    last_mono: u64 = 0,
    resumes: u32 = 0,
};
pub fn main(init: std.process.Init.Minimal) u8 {
    run(init) catch |err| {
        @import("log.zig").msg(&.{ "[monitor] exit: ", @errorName(err) });
        return 1;
    };
    return 0;
}
fn run(init: std.process.Init.Minimal) !void {
    var args = init.args.iterate();
    _ = args.next();
    const socket_path = args.next() orelse return error.MissingSocket;
    const history_path = args.next() orelse return error.MissingHistoryDirectory;
    @import("source.zig").root = args.next() orelse "";
    if (args.next() != null) return error.TooManyArguments;
    var persistence = Persistence{ .directory = history_path };
    persistence.restore(&store, sys.wallMs());
    defer persistence.deinit();
    if (persistence.lock_conflict) return error.HistoryAlreadyInUse;
    defer {
        if (store.flush()) |a| persistence.add(a);
        persistence.flush();
    }
    var sampler = Sampler.init();
    defer sampler.deinit();
    var io = IoStats.init();
    defer io.deinit();
    const device = Device.init();
    if (@import("source.zig").root.len == 0) net = Netlink.init();
    defer net.deinit();
    var state = State{ .started = sys.nowMs() };
    state.last = sampler.sample();
    const fd = try sys.connectUnix(socket_path);
    defer sys.close(fd);
    const tfd = try sys.timerfdCreate();
    defer sys.close(tfd);
    try sys.timerfdSet(tfd, state.interval_ms);
    const efd = try sys.epollCreate();
    defer sys.close(efd);
    try sys.epollAdd(efd, tfd, 1);
    try sys.epollAdd(efd, fd, 2);
    if (net.fd >= 0) try sys.epollAdd(efd, net.fd, 3);
    var events: [8]sys.EpollEvent = undefined;
    while (true) {
        const n = sys.epollWait(efd, &events);
        if (n == 0) return error.EventLoopFailed;
        for (events[0..n]) |ev| {
            if (ev.data.u32 == 1) {
                sys.timerfdDrain(tfd);
                try tick(&state, &sampler, &io, &persistence);
            } else if (ev.data.u32 == 3) {
                net.read();
            } else if (ev.data.u32 == 2) {
                if (ev.events & sys.IN != 0) transport.receive(fd) catch |err| {
                    if (err == error.Closed) return;
                    return err;
                };
                if (ev.events & sys.IN == 0 and ev.events & sys.OUT == 0) return;
            }
        }
        // Bounded receive buffer, at most sixteen complete requests per loop turn.
        var handled: usize = 0;
        while (transport.line()) |line| {
            const len = line.len;
            if (handled == 16) return error.RequestFlood;
            try handle(line, &state, &sampler, &device, &persistence, tfd);
            transport.consume(len + 1);
            handled += 1;
        }
        try transport.flush(fd);
        try sys.epollInterest(efd, fd, 2, transport.out_len > transport.out_pos);
    }
}
fn tick(state: *State, sampler: *Sampler, io: *IoStats, persistence: *Persistence) !void {
    const mono = sys.nowMs();
    const boot = sys.bootMs();
    if (state.last_boot > 0 and boot -| state.last_boot > (mono -| state.last_mono) + 2000) {
        if (store.flush()) |a| persistence.add(a);
        store.last_wall = 0;
        store.mid_bucket = null;
        store.lo_bucket = null;
        store.gaps += 1;
        sampler.reset();
        io.deinit();
        io.* = IoStats.init();
        state.resumes += 1;
    }
    state.last_boot = boot;
    state.last_mono = mono;
    const begin = sys.nowUs();
    state.last = sampler.sample();
    io.sample(&state.last, net.interface(), sys.nowUs());
    const elapsed = sys.nowUs() -| begin;
    state.sample_total_us += elapsed;
    state.sample_max_us = @max(state.sample_max_us, elapsed);
    state.samples += 1;
    if (store.push(state.last, mono)) |a| persistence.add(a);
    if (state.live and mono -| state.last_sent_ms >= 1000 and changed(state.last_sent, state.last)) {
        var w = std.Io.Writer.fixed(&response);
        try w.writeAll("{\"type\":\"event\",\"name\":\"metrics\",\"data\":");
        try M.writeValues(&w, &state.last);
        try w.writeAll("}\n");
        try transport.queue(w.buffered());
        state.last_sent = state.last;
        state.last_sent_ms = mono;
    }
}
fn handle(line: []const u8, state: *State, sampler: *Sampler, device: *const Device, persistence: *Persistence, tfd: i32) !void {
    var w = std.Io.Writer.fixed(&response);
    const request = proto.parse(line, &parse_memory) catch {
        state.protocol_errors += 1;
        try proto.failure(&w, proto.requestId(line, &parse_memory), "invalid_request");
        try transport.queue(w.buffered());
        return;
    };
    const method = request.method;
    const supported = std.mem.eql(u8, method, "get_status") or std.mem.eql(u8, method, "get_device_info") or
        std.mem.eql(u8, method, "set_config") or std.mem.eql(u8, method, "query_history") or
        std.mem.eql(u8, method, "get_connectivity") or std.mem.eql(u8, method, "flush") or std.mem.eql(u8, method, "export_summary");
    if (!supported) {
        state.protocol_errors += 1;
        try proto.failure(&w, request.id, "unsupported_method");
        try transport.queue(w.buffered());
        return;
    }
    try w.print("{{\"type\":\"response\",\"id\":{d},\"ok\":true,\"data\":", .{request.id});
    if (std.mem.eql(u8, method, "get_status")) {
        try w.print("{{\"version\":\"" ++ M.version ++ "\",\"interval_ms\":{d},\"live_push\":{},\"uptime_ms\":{d},\"samples\":{d},\"sample_total_us\":{d},\"sample_max_us\":{d},\"protocol_errors\":{d},\"hi_len\":{d},\"mid_len\":{d},\"lo_len\":{d},\"persistence_failed\":{},\"invalid_history_files\":{d},\"bytes_written\":{d},\"clock_changes\":{d},\"resumes\":{d},\"cpu_online\":{d},\"topology_truncated\":{},\"latest\":", .{
            state.interval_ms,         state.live,          sys.nowMs() -| state.started, state.samples,  state.sample_total_us,      state.sample_max_us,
            state.protocol_errors,     store.hi.len,        store.mid.len,                store.lo.len,   persistence.failed,         persistence.invalid_files,
            persistence.bytes_written, store.clock_changes, state.resumes,                sampler.online, sampler.topology_truncated,
        });
        try M.writeValues(&w, &state.last);
        try w.writeAll(",\"cpu_threads_x10\":[");
        for (sampler.threads, 0..) |v, i| {
            if (i > 0) try w.writeByte(',');
            if (v) |value| try w.print("{d}", .{value}) else try w.writeAll("null");
        }
        try w.writeAll("],\"sources\":{\"cpu_temperature\":");
        try proto.string(&w, @import("device.zig").z(&sampler.sensors.cpu_source));
        try w.writeAll(",\"battery\":");
        try proto.string(&w, @import("device.zig").z(&sampler.sensors.battery_source));
        try w.writeAll(",\"gpu\":");
        try proto.string(&w, @import("device.zig").z(&sampler.sensors.gpu_source));
        try w.writeAll(",\"battery_power\":");
        try proto.string(&w, sampler.sensors.batteryPowerSource());
        try w.writeAll("},\"sensor_cache\":{\"nvme_period_ms\":30000,\"nvme_age_ms\":");
        if (sampler.sensors.nvme_value != null and sampler.sensors.nvme_read_us != null) {
            try w.print("{d}", .{(sys.nowUs() -| sampler.sensors.nvme_read_us.?) / 1000});
        } else try w.writeAll("null");
        try w.writeAll("}}");
    } else if (std.mem.eql(u8, method, "get_device_info") or std.mem.eql(u8, method, "export_summary")) {
        try device.write(&w);
    } else if (std.mem.eql(u8, method, "get_connectivity")) {
        try net.write(&w);
    } else if (std.mem.eql(u8, method, "set_config")) {
        if (request.args.interval_ms) |ms| {
            try sys.timerfdSet(tfd, ms);
            state.interval_ms = ms;
        }
        if (request.args.live_push) |live| {
            state.live = live;
            state.last_sent = null;
        }
        try w.writeAll("{}");
    } else if (std.mem.eql(u8, method, "query_history")) {
        try proto.history(&w, &store, request.args);
    } else {
        if (store.flush()) |a| persistence.add(a);
        persistence.flush();
        try w.print("{{\"persistence_failed\":{}}}", .{persistence.failed});
    }
    try w.writeAll("}\n");
    try transport.queue(w.buffered());
}
fn changed(last: ?M.Sample, current: M.Sample) bool {
    const previous = last orelse return true;
    if (current.available != previous.available) return true;
    for (current.values, previous.values, 0..) |a, b, i| {
        if (current.available & (@as(u32, 1) << @intCast(i)) == 0) continue;
        const threshold: u32 = switch (@as(M.Metric, @enumFromInt(i))) {
            .cpu_pct_x10 => 20,
            .cpu_temp_mc, .gpu_temp_mc, .nvme_temp_mc => 500,
            .mem_used_mb, .mem_total_mb, .swap_used_mb => 32,
            .apu_power_mw, .battery_rate_mw => 300,
            .gpu_pct => 3,
            else => 1,
        };
        if (@abs(@as(i64, a) - b) >= threshold) return true;
    }
    return false;
}
