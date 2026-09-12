//! Bounded battery metadata for the QAM manual snapshot.
//!
//! This module deliberately follows the sampler's selected source; it never
//! searches power_supply itself. All reads go through source.zig so a nonempty
//! source.root remains a complete sysfs fixture boundary.
const std = @import("std");
const src = @import("source.zig");
const proto = @import("protocol.zig");

const Pair = struct {
    full: ?i64,
    design: ?i64,
};

const Capacity = struct {
    basis: ?[]const u8 = null,
    full: ?i64 = null,
    design: ?i64 = null,
    unit: ?[]const u8 = null,
    health_x10: ?i64 = null,
};

/// Write one bounded JSON object for `selected`, the basename retained by the
/// sampler. An empty or unsafe selection is reported as an absent battery.
pub fn write(w: *std.Io.Writer, selected: []const u8) !void {
    if (!safeBasename(selected)) return absent(w);

    const present = attributeInt(selected, "present");
    const energy = Pair{
        .full = attributeInt(selected, "energy_full"),
        .design = attributeInt(selected, "energy_full_design"),
    };
    const charge = Pair{
        .full = attributeInt(selected, "charge_full"),
        .design = attributeInt(selected, "charge_full_design"),
    };
    const capacity = chooseCapacity(energy, charge);

    try w.writeAll("{\"present\":");
    if (present) |value| try w.writeAll(if (value == 1) "true" else if (value == 0) "false" else "null") else try w.writeAll("null");
    try w.writeAll(",\"source\":");
    try proto.string(w, selected);
    try w.writeAll(",\"status\":");
    var status_buf: [64]u8 = undefined;
    if (attributeText(selected, "status", &status_buf)) |status| {
        if (standardStatus(status)) try proto.string(w, status) else try w.writeAll("null");
    } else try w.writeAll("null");
    try w.writeAll(",\"capacity_basis\":");
    try optionalString(w, capacity.basis);
    try w.writeAll(",\"full_capacity\":");
    try optionalInt(w, capacity.full);
    try w.writeAll(",\"design_capacity\":");
    try optionalInt(w, capacity.design);
    try w.writeAll(",\"capacity_unit\":");
    try optionalString(w, capacity.unit);
    try w.writeAll(",\"health_pct_x10\":");
    try optionalInt(w, capacity.health_x10);
    try w.writeAll(",\"cycle_count\":");
    try optionalInt(w, nonnegative(attributeInt(selected, "cycle_count")));
    try w.writeAll(",\"voltage_mv\":");
    try optionalInt(w, millivalue(nonnegative(attributeInt(selected, "voltage_now"))));
    try w.writeByte('}');
}

fn absent(w: *std.Io.Writer) !void {
    try w.writeAll("{\"present\":false,\"source\":null,\"status\":null,\"capacity_basis\":null,\"full_capacity\":null,\"design_capacity\":null,\"capacity_unit\":null,\"health_pct_x10\":null,\"cycle_count\":null,\"voltage_mv\":null}");
}

fn optionalString(w: *std.Io.Writer, value: ?[]const u8) !void {
    if (value) |text| try proto.string(w, text) else try w.writeAll("null");
}

fn optionalInt(w: *std.Io.Writer, value: ?i64) !void {
    if (value) |number| try w.print("{d}", .{number}) else try w.writeAll("null");
}

/// Attribute paths are assembled only from a safe selected basename and a
/// compile-time whitelist at each call site. source.zig prepends source.root.
fn attributeText(selected: []const u8, comptime attribute: []const u8, buf: []u8) ?[]const u8 {
    var path_buf: [192]u8 = undefined;
    const path = src.join(&path_buf, "/sys/class/power_supply/{s}/" ++ attribute, .{selected}) orelse return null;
    return src.text(path, buf);
}

fn attributeInt(selected: []const u8, comptime attribute: []const u8) ?i64 {
    var buf: [64]u8 = undefined;
    return src.integer(attributeText(selected, attribute, &buf) orelse return null);
}

fn safeBasename(name: []const u8) bool {
    if (name.len == 0 or name.len > 63) return false;
    if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) return false;
    for (name) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '-' or byte == '.') continue;
        return false;
    }
    return true;
}

fn standardStatus(value: []const u8) bool {
    inline for (.{ "Charging", "Discharging", "Full", "Not charging", "Unknown" }) |known| {
        if (std.mem.eql(u8, value, known)) return true;
    }
    return false;
}

fn nonnegative(value: ?i64) ?i64 {
    const number = value orelse return null;
    return if (number >= 0) number else null;
}

fn millivalue(value: ?i64) ?i64 {
    const number = value orelse return null;
    return @divTrunc(number, 1000);
}

fn validDesign(value: ?i64) ?i64 {
    const number = value orelse return null;
    return if (number > 0) number else null;
}

fn chooseCapacity(energy_raw: Pair, charge_raw: Pair) Capacity {
    const energy = Pair{ .full = nonnegative(energy_raw.full), .design = validDesign(energy_raw.design) };
    const charge = Pair{ .full = nonnegative(charge_raw.full), .design = validDesign(charge_raw.design) };
    const energy_complete = energy.full != null and energy.design != null;
    const charge_complete = charge.full != null and charge.design != null;
    const is_energy = if (energy_complete) true else if (charge_complete) false else energy.full != null or energy.design != null;
    const chosen = if (is_energy) energy else if (charge.full != null or charge.design != null) charge else return .{};
    return .{
        .basis = if (is_energy) "energy" else "charge",
        .full = millivalue(chosen.full),
        .design = millivalue(chosen.design),
        .unit = if (is_energy) "mWh" else "mAh",
        .health_x10 = healthX10(chosen.full, chosen.design),
    };
}

/// Return full/design * 1000 without i64 overflow. Inputs are raw micro-units
/// so rounding capacity values for display cannot distort the health estimate.
fn healthX10(full: ?i64, design: ?i64) ?i64 {
    const numerator = nonnegative(full) orelse return null;
    const denominator = validDesign(design) orelse return null;
    const result: i128 = @divTrunc(@as(i128, numerator) * 1000, @as(i128, denominator));
    if (result > std.math.maxInt(i64)) return null;
    return @intCast(result);
}

test "normal energy capacity is converted and reports health" {
    const capacity = chooseCapacity(.{ .full = 40_000_000, .design = 50_000_000 }, .{ .full = 9, .design = 9 });
    try std.testing.expectEqualStrings("energy", capacity.basis.?);
    try std.testing.expectEqual(@as(?i64, 40_000), capacity.full);
    try std.testing.expectEqual(@as(?i64, 50_000), capacity.design);
    try std.testing.expectEqual(@as(?i64, 800), capacity.health_x10);
    try std.testing.expectEqualStrings("mWh", capacity.unit.?);
}

test "charge fallback does not fabricate an energy conversion" {
    const capacity = chooseCapacity(.{ .full = null, .design = null }, .{ .full = 4_000_000, .design = 5_000_000 });
    try std.testing.expectEqualStrings("charge", capacity.basis.?);
    try std.testing.expectEqual(@as(?i64, 4_000), capacity.full);
    try std.testing.expectEqual(@as(?i64, 5_000), capacity.design);
    try std.testing.expectEqualStrings("mAh", capacity.unit.?);
}

test "complete charge pair supersedes incomplete energy data" {
    const capacity = chooseCapacity(.{ .full = 40_000_000, .design = null }, .{ .full = 4_000_000, .design = 5_000_000 });
    try std.testing.expectEqualStrings("charge", capacity.basis.?);
    try std.testing.expectEqual(@as(?i64, 800), capacity.health_x10);
}

test "missing capacity remains unavailable" {
    const capacity = chooseCapacity(.{ .full = null, .design = null }, .{ .full = null, .design = null });
    try std.testing.expect(capacity.basis == null);
    try std.testing.expect(capacity.full == null);
    try std.testing.expect(capacity.health_x10 == null);
}

test "health overflow is rejected" {
    const capacity = chooseCapacity(.{ .full = std.math.maxInt(i64), .design = 1 }, .{ .full = null, .design = null });
    try std.testing.expect(capacity.full != null);
    try std.testing.expect(capacity.health_x10 == null);
}

test "unsafe selected source is rejected" {
    try std.testing.expect(safeBasename("BAT0"));
    try std.testing.expect(!safeBasename("../BAT0"));
    try std.testing.expect(!safeBasename("BAT0/x"));
    try std.testing.expect(!safeBasename(".."));
}

test "zero design capacity has no health estimate" {
    const capacity = chooseCapacity(.{ .full = 40_000_000, .design = 0 }, .{ .full = null, .design = null });
    try std.testing.expectEqualStrings("energy", capacity.basis.?);
    try std.testing.expectEqual(@as(?i64, 40_000), capacity.full);
    try std.testing.expect(capacity.design == null);
    try std.testing.expect(capacity.health_x10 == null);
}

test "writer reads only the selected battery below fixture root" {
    var fixture = std.testing.tmpDir(.{});
    defer fixture.cleanup();
    try fixture.dir.createDirPath(std.testing.io, "sys/class/power_supply/BAT0");
    inline for (.{
        .{ "present", "1\n" },
        .{ "status", "Charging\n" },
        .{ "energy_full", "40000000\n" },
        .{ "energy_full_design", "50000000\n" },
        .{ "cycle_count", "12\n" },
        .{ "voltage_now", "15432000\n" },
    }) |file| {
        try fixture.dir.writeFile(std.testing.io, .{
            .sub_path = "sys/class/power_supply/BAT0/" ++ file[0],
            .data = file[1],
        });
    }

    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try fixture.dir.realPath(std.testing.io, &root_buf);
    const saved_root = src.root;
    src.root = root_buf[0..root_len];
    defer src.root = saved_root;

    var output: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output);
    try write(&writer, "BAT0");
    try std.testing.expectEqualStrings(
        "{\"present\":true,\"source\":\"BAT0\",\"status\":\"Charging\",\"capacity_basis\":\"energy\",\"full_capacity\":40000,\"design_capacity\":50000,\"capacity_unit\":\"mWh\",\"health_pct_x10\":800,\"cycle_count\":12,\"voltage_mv\":15432}",
        writer.buffered(),
    );
}
