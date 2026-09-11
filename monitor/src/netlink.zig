const std = @import("std");
const sys = @import("sys.zig");
const proto = @import("protocol.zig");
const z = @import("device.zig").z;
const Link = struct { index: u32 = 0, flags: u32 = 0, name: [16]u8 = @splat(0) };
const Address = struct { index: u32 = 0, family: u8 = 0, scope: u8 = 0, flags: u32 = 0, bytes: [16]u8 = @splat(0) };
const Route = struct { index: u32 = 0, family: u8 = 0, metric: u32 = 0 };
const Cache = struct {
    links: [64]Link = @splat(.{}),
    link_count: usize = 0,
    addresses: [128]Address = @splat(.{}),
    address_count: usize = 0,
    routes: [64]Route = @splat(.{}),
    route_count: usize = 0,
    truncated: bool = false,
};
pub const Netlink = struct {
    fd: i32 = -1,
    active: Cache = .{},
    next: Cache = .{},
    seq: u32 = 1,
    stage: u8 = 0,
    dirty: bool = false,
    ready: bool = false,
    failed: bool = false,
    pub fn init() Netlink {
        var self = Netlink{};
        self.fd = sys.routeSocket() catch {
            self.failed = true;
            return self;
        };
        self.refresh() catch {
            self.failed = true;
        };
        return self;
    }
    pub fn deinit(self: *Netlink) void {
        if (self.fd >= 0) sys.close(self.fd);
    }
    pub fn refresh(self: *Netlink) !void {
        if (self.fd < 0) return;
        if (self.stage != 0) {
            self.dirty = true;
            return;
        }
        self.next = .{};
        self.stage = 1;
        self.seq +%= 1;
        try sys.routeDump(self.fd, 18, self.seq); // RTM_GETLINK
    }
    pub fn read(self: *Netlink) void {
        var buf: [32768]u8 = undefined;
        // Bounded work: excess datagrams keep the level-triggered fd readable.
        for (0..8) |_| {
            const n = sys.recv(self.fd, &buf) catch |err| {
                if (err != error.Again) self.failed = true;
                return;
            };
            if (n == buf.len) self.next.truncated = true;
            self.messages(buf[0..n]) catch {
                self.failed = true;
                self.stage = 0;
                return;
            };
        }
    }
    fn messages(self: *Netlink, data: []const u8) !void {
        var pos: usize = 0;
        while (pos + 16 <= data.len) {
            const len = u32at(data[pos..], 0);
            if (len < 16 or len > data.len - pos) return error.InvalidMessage;
            const msg = data[pos..][0..len];
            const kind = u16at(msg, 4);
            const seq = u32at(msg, 8);
            pos += align4(len);
            if (seq == 0) {
                self.dirty = true;
                continue;
            }
            if (seq != self.seq) continue;
            if (kind == 2) {
                if (len < 20 or u32at(msg, 16) != 0) return error.KernelError;
                continue;
            }
            if (kind == 3) {
                if (self.stage == 1) {
                    self.stage = 2;
                    self.seq +%= 1;
                    try sys.routeDump(self.fd, 22, self.seq);
                } else if (self.stage == 2) {
                    self.stage = 3;
                    self.seq +%= 1;
                    try sys.routeDump(self.fd, 26, self.seq);
                } else {
                    self.active = self.next;
                    self.ready = true;
                    self.failed = false;
                    self.stage = 0;
                }
                continue;
            }
            if (kind == 16) self.parseLink(msg);
            if (kind == 20) self.address(msg);
            if (kind == 24) self.route(msg);
        }
        if (self.stage == 0 and self.dirty) {
            self.dirty = false;
            try self.refresh();
        }
    }
    fn parseLink(self: *Netlink, msg: []const u8) void {
        if (msg.len < 32) return;
        var l = Link{ .index = u32at(msg, 20), .flags = u32at(msg, 24) };
        var attrs = Attributes{ .data = msg[32..] };
        while (attrs.next()) |a| if (a.kind == 3) {
            const n = @min(15, z(a.data).len);
            @memcpy(l.name[0..n], a.data[0..n]);
        };
        if (self.next.link_count == self.next.links.len) {
            self.next.truncated = true;
            return;
        }
        self.next.links[self.next.link_count] = l;
        self.next.link_count += 1;
    }
    fn address(self: *Netlink, msg: []const u8) void {
        if (msg.len < 24 or (msg[16] != 2 and msg[16] != 10)) return;
        var addr = Address{ .family = msg[16], .flags = msg[18], .scope = msg[19], .index = u32at(msg, 20) };
        const width: usize = if (addr.family == 2) 4 else 16;
        var found = false;
        var local = false;
        var attrs = Attributes{ .data = msg[24..] };
        while (attrs.next()) |a| {
            if ((a.kind == 1 or a.kind == 2) and a.data.len >= width and (!local or a.kind == 2)) {
                @memcpy(addr.bytes[0..width], a.data[0..width]);
                found = true;
                if (a.kind == 2) local = true;
            }
            if (a.kind == 8 and a.data.len >= 4) addr.flags = u32at(a.data, 0);
        }
        if (!found) return;
        if (self.next.address_count == self.next.addresses.len) {
            self.next.truncated = true;
            return;
        }
        self.next.addresses[self.next.address_count] = addr;
        self.next.address_count += 1;
    }
    fn route(self: *Netlink, msg: []const u8) void {
        if (msg.len < 28 or msg[17] != 0 or msg[23] != 1) return; // default unicast only
        var r = Route{ .family = msg[16] };
        var table: u32 = msg[20];
        var attrs = Attributes{ .data = msg[28..] };
        while (attrs.next()) |a| {
            if (a.data.len < 4) continue;
            if (a.kind == 4) r.index = u32at(a.data, 0);
            if (a.kind == 6) r.metric = u32at(a.data, 0);
            if (a.kind == 15) table = u32at(a.data, 0);
        }
        if (table != 254 or r.index == 0) return;
        if (self.next.route_count == self.next.routes.len) {
            self.next.truncated = true;
            return;
        }
        self.next.routes[self.next.route_count] = r;
        self.next.route_count += 1;
    }
    pub fn recommended(self: *const Netlink) ?Address {
        var best: ?Address = null;
        var best_score: u8 = 255;
        var best_metric: u32 = std.math.maxInt(u32);
        for (self.active.addresses[0..self.active.address_count]) |addr| {
            if (!eligible(addr)) continue;
            const link = self.findLink(addr.index) orelse continue;
            if (link.flags & 1 == 0 or virtual(z(&link.name))) continue;
            var metric: ?u32 = null;
            for (self.active.routes[0..self.active.route_count]) |r| {
                if (r.index == addr.index and r.family == addr.family) metric = @min(metric orelse std.math.maxInt(u32), r.metric);
            }
            const m = metric orelse continue;
            // Respect default-route metric within each family, then rank address types.
            var lower_route = false;
            for (self.active.routes[0..self.active.route_count]) |r| {
                if (r.family == addr.family and r.metric < m) {
                    if (self.findLink(r.index)) |l| {
                        if (l.flags & 1 != 0 and !virtual(z(&l.name))) lower_route = true;
                    }
                }
            }
            if (lower_route) continue;
            const score: u8 = if (addr.family == 2 and private4(addr.bytes)) 0 else if (addr.family == 10 and addr.bytes[0] & 0xfe == 0xfc) 1 else 2;
            if (best == null or score < best_score or (score == best_score and m < best_metric)) {
                best = addr;
                best_score = score;
                best_metric = m;
            }
        }
        return best;
    }
    fn findLink(self: *const Netlink, index: u32) ?Link {
        for (self.active.links[0..self.active.link_count]) |link| if (link.index == index) return link;
        return null;
    }
    pub fn interface(self: *const Netlink) ?[]const u8 {
        const addr = self.recommended() orelse return null;
        for (self.active.links[0..self.active.link_count]) |*link| if (link.index == addr.index) return z(&link.name);
        return null;
    }
    pub fn write(self: *const Netlink, w: *std.Io.Writer) !void {
        try w.print("{{\"ready\":{},\"failed\":{},\"truncated\":{},\"recommended_ip\":", .{ self.ready, self.failed, self.active.truncated });
        if (self.recommended()) |addr| {
            var buf: [64]u8 = undefined;
            try proto.string(w, formatAddress(&buf, addr));
        } else try w.writeAll("null");
        try w.writeAll(",\"interface\":");
        if (self.interface()) |name| try proto.string(w, name) else try w.writeAll("null");
        try w.writeAll(",\"routing_scope\":\"main_table\"");
        try @import("service.zig").write(w);
        try w.writeByte('}');
    }
};
const Attribute = struct { kind: u16, data: []const u8 };
const Attributes = struct {
    data: []const u8,
    fn next(self: *Attributes) ?Attribute {
        if (self.data.len < 4) return null;
        const len = u16at(self.data, 0);
        if (len < 4 or len > self.data.len) {
            self.data = "";
            return null;
        }
        const out: Attribute = .{ .kind = u16at(self.data, 2) & 0x3fff, .data = self.data[4..len] };
        self.data = self.data[@min(align4(len), self.data.len)..];
        return out;
    }
};
fn u16at(b: []const u8, i: usize) u16 {
    return std.mem.readInt(u16, b[i..][0..2], .little);
}
fn u32at(b: []const u8, i: usize) u32 {
    return std.mem.readInt(u32, b[i..][0..4], .little);
}
fn align4(n: usize) usize {
    return (n + 3) & ~@as(usize, 3);
}
fn virtual(name: []const u8) bool {
    inline for (.{ "lo", "tun", "tap", "wg", "docker", "veth", "virbr", "tailscale", "Cloudflare" }) |prefix| if (std.mem.startsWith(u8, name, prefix)) return true;
    return false;
}
fn private4(a: [16]u8) bool {
    return a[0] == 10 or (a[0] == 172 and a[1] >= 16 and a[1] <= 31) or (a[0] == 192 and a[1] == 168);
}
fn eligible(a: Address) bool {
    if (a.scope != 0 or a.flags & (0x20 | 0x40 | 0x08) != 0) return false; // deprecated/tentative/DAD failed
    if (a.family == 2) return a.bytes[0] != 0 and a.bytes[0] != 127 and a.bytes[0] < 224 and !(a.bytes[0] == 169 and a.bytes[1] == 254);
    return a.family == 10 and a.flags & 1 == 0 and a.bytes[0] != 0xff and !(a.bytes[0] == 0xfe and a.bytes[1] & 0xc0 == 0x80) and !std.mem.allEqual(u8, a.bytes[0..15], 0);
}
fn formatAddress(buf: []u8, a: Address) []const u8 {
    if (a.family == 2) return std.fmt.bufPrint(buf, "{d}.{d}.{d}.{d}", .{ a.bytes[0], a.bytes[1], a.bytes[2], a.bytes[3] }) catch "";
    var w = std.Io.Writer.fixed(buf);
    for (0..8) |i| {
        if (i > 0) w.writeByte(':') catch return "";
        w.print("{x}", .{std.mem.readInt(u16, a.bytes[i * 2 ..][0..2], .big)}) catch return "";
    }
    return w.buffered();
}
test "address filtering respects scope privacy and DAD" {
    var a = Address{ .family = 2, .bytes = .{ 192, 168, 1, 2 } ++ @as([12]u8, @splat(0)) };
    try std.testing.expect(eligible(a));
    a.flags = 0x40;
    try std.testing.expect(!eligible(a));
    a.flags = 0;
    a.bytes[0] = 127;
    try std.testing.expect(!eligible(a));
}
test "malformed netlink lengths do not escape datagram" {
    var net = Netlink{};
    var bytes: [16]u8 = @splat(0);
    bytes[0] = 40;
    try std.testing.expectError(error.InvalidMessage, net.messages(&bytes));
}
