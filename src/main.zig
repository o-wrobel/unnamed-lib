const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const wgpu = @import("wgpu");
const glfw = @import("glfw");
const Window = glfw.Window;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    _ = gpa; // autofix

    // WGPU
    const instance = try wgpu.Instance.init(null);
    defer instance.deinit();
    const adapter = try instance.requestAdapterSync(.{});
    defer adapter.deinit();

    const info = try adapter.getInfo();
    std.log.info("Device name: {s}", .{info.device});

    const device_desc: wgpu.Device.Descriptor = .{
        .label = "My Cool Device",
        .queue_label = "Default Queue"
    };
    const device = try adapter.requestDeviceSync(device_desc);
    defer device.deinit();
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

    // GLFW
    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.client_api, .no_api);
    glfw.windowHint(.resizable, false);
    const window: *Window = try .create(400, 400, "Hello, GLFW!", null, null);
    defer window.destroy();

    // Get native window handle and create a wgpu surface
    var source = wgpu.c.WGPUSurfaceSourceWaylandSurface{
        .chain = .{
            .next = null,
            .sType = wgpu.c.WGPUSType_SurfaceSourceWaylandSurface,
        },
        .display = glfw.getWaylandDisplay() orelse @panic("No Wayland display"),
        .surface = glfw.getWaylandWindow(window) orelse @panic("No Wayland surface"),
    };

    var surface_desc = wgpu.c.WGPUSurfaceDescriptor{
        .nextInChain = @ptrCast(&source.chain),
        .label = .{ .data = "Surface", .length = "Surface".len },
    };

    const surface = try instance.createSurface(&surface_desc);
    defer surface.deinit();
    std.log.info("Surface created successfully!", .{});

    // Query supported formats and pick the first one
    const surface_capabilities = try surface.getCapabilities(adapter.adapter);
    const format = surface_capabilities.formats[0];

    surface.configure(.{
        .width = 400,
        .height = 400,
        .format = format,
        .usage = .{ .render_attachment = true }, // The surface is a target for a render pass
        .device = device,
    });
    const current_surface_texture_result = surface.getCurrentTexture();
    const texture = current_surface_texture_result.success;
    defer texture.deinit();

    const view: wgpu.TextureView = try .init(
        texture.texture,
        wgpu.TextureView.Descriptor{
            .label = "Surface texture view",
            .format = texture.getFormat(),
            .dimension = .@"2d",
            .aspect = .all
        }
    );
    defer view.deinit();

    try surface.present();

    // MAIN LOOP
    std.log.info("Running main loop...", .{});
    while (true) {
        if (glfw.windowShouldClose(window)) break;
        glfw.pollEvents();
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
