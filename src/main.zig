const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const wgpu = @import("wgpu");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    _ = gpa; // autofix

    const instance = try wgpu.Instance.init(null);
    const adapter = try instance.requestAdapterSync(.{});
    instance.deinit();

    const info = try adapter.getInfo();
    std.log.info("Device name: {s}", .{info.device});

    const device_desc: wgpu.Device.Descriptor = .{
        .label = "My Cool Device",
        .queue_label = "Default Queue"
    };
    const device = try adapter.requestDeviceSync(device_desc);
    defer device.deinit();
    adapter.deinit();
    // TODO: Set up callback functions

    const encoder = try device.createCommandEncoder(.{ .label = "My command encoder"});

    encoder.insertDebugMarker("This is a debug marker");
    const command_buffer = try encoder.finish(.{ .label = "Command buffer" });
    encoder.deinit();

    const queue = try device.getQueue();
    defer queue.deinit();
    queue.registerWorkDoneCallback(.{ .callback = onQueueWorkDone });
    std.log.info("Submitting command...", .{});
    queue.submitCommands(&.{command_buffer});
    std.log.info("Command submitted", .{});

    for (0..5) |_| {
        std.log.info("Tick/poll device", .{});

        _ = device.poll(true);
    }
}

fn onQueueWorkDone(
    status: wgpu.c.WGPUQueueWorkDoneStatus,
    message: wgpu.c.struct_WGPUStringView,
    userdata1: ?*anyopaque,
    userdata2: ?*anyopaque
) callconv(.c) void {
    _ = message; // autofix
    _ = userdata1; // autofix
    _ = userdata2; // autofix
    std.log.info("Work done! Finished with status: {}", .{status});
}

fn printLimits(limits: wgpu.c.WGPULimits) void {
    const fields = @typeInfo(@TypeOf(limits)).@"struct".fields;
    inline for (fields) |f| {
        const val = @field(limits, f.name);
        if (@typeInfo(f.type) != .pointer) {
            std.log.info("{s}: {}", .{ f.name,  val});
        } else {
            std.log.info("{s}: @{*}", .{ f.name,  val});
        }
    }
}
