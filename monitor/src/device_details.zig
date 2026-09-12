const std = @import("std");
const Device = @import("device.zig").Device;
pub fn write(w: *std.Io.Writer, device: *const Device, battery: []const u8) !void {
    var buffer: [8192]u8 = undefined;
    var header = std.Io.Writer.fixed(&buffer);
    try device.write(&header);
    const data = header.buffered();
    if (data.len == 0 or data[data.len - 1] != '}') return error.InvalidDeviceInfo;
    try w.writeAll(data[0 .. data.len - 1]);
    try w.writeAll(",\"battery\":");
    try @import("battery_details.zig").write(w, battery);
    try w.writeAll(",\"storage\":");
    try @import("storage_details.zig").write(w);
    try w.writeAll(",\"system\":");
    try @import("system_details.zig").write(w);
    try w.writeByte('}');
}
