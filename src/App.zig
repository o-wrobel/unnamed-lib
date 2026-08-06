const std = @import("std");
const wgpu = @import("wgpu");
const glfw = @import("glfw");
const Window = glfw.Window;

const window_width = 400;
const window_height = 400;

pub const App = @This();

const log = std.log.scoped(.App);

window: *Window,
device: wgpu.Device,
queue: wgpu.Queue,
surface: wgpu.Surface,

pub fn init() !App {
    log.info("Initializing", .{});
    // GLFW
    try glfw.init();

    glfw.windowHint(.client_api, .no_api);
    glfw.windowHint(.resizable, false);
    log.info("Creating window", .{});
    const window: *Window = try .create(window_width, window_height, "Hello, GLFW!", null, null);

    // WGPU
    const instance = try wgpu.Instance.init(null);
    defer instance.deinit();

    const adapter = try instance.requestAdapterSync(.{});

    const device_desc: wgpu.Device.Descriptor = .{
        .label = "My Cool Device",
        .queue_label = "Default Queue"
    };
    const device = try adapter.requestDeviceSync(device_desc);
    // TODO: Set up callback functions

    const queue = try device.getQueue();

    // Get native window handle and create a wgpu surface
    var source = wgpu.c.WGPUSurfaceSourceWaylandSurface{
        .chain = .{
            .next = null,
            .sType = wgpu.c.WGPUSType_SurfaceSourceWaylandSurface,
        },
        .display = glfw.getWaylandDisplay() orelse @panic("No Wayland display"),
        .surface = glfw.getWaylandWindow(window) orelse @panic("No Wayland surface"),
    };

    const surface_desc = wgpu.c.WGPUSurfaceDescriptor{
        .nextInChain = @ptrCast(&source.chain),
        .label = .{ .data = "Surface", .length = "Surface".len },
    };

    const surface = try instance.createSurface(&surface_desc);

    const surface_capabilities = try surface.getCapabilities(adapter.adapter);
    const format = surface_capabilities.formats[0];

    surface.configure(.{
        .width = 400,
        .height = 400,
        .format = format,
        .usage = .{ .render_attachment = true }, // The surface is a target for a render pass
        .device = device,
    });

    return .{
        .window = window,
        .device = device,
        .queue = queue,
        .surface = surface
    };
}

pub fn deinit(self: App) void {
    log.info("Deinitializing", .{});
    self.device.deinit();
    self.queue.deinit();
    self.surface.deinit();
    self.window.destroy();
}

pub fn mainLoop(self: *const App) !void {
    while (true) {
        glfw.pollEvents();
        if (glfw.windowShouldClose(self.window)) break;
        const target_view = try getNextSurfaceTextureView(self.surface);
        const encoder = try self.device.createCommandEncoder(.{ .label = "My command encoder" });
        defer encoder.deinit();

        const color_attachment: wgpu.RenderPassEncoder.ColorAttachment = .{
            .view = target_view,
            .clear_value = color(0.9, 0.1, 0.5, 1),
            .load_op = .clear,
            .store_op = .store,
        };

        const render_pass = try encoder.beginRenderPass(.{
            .color_attachments = &.{color_attachment},
            .label = "My render pass"
        });

        // Stuff goes here, right now the screen is only cleared

        render_pass.end();
        render_pass.deinit();

        const command = try encoder.finish(.{ .label = "Command buffer" });

        std.log.debug("Submitting command...", .{});
        self.queue.submitCommands(&.{command});
        std.log.debug("Command submitted", .{});

        try self.surface.present();

        target_view.deinit();
        _ = self.device.poll(false);
    }
}

fn getNextSurfaceTextureView(surface: wgpu.Surface) !wgpu.TextureView {
     const result = surface.getCurrentTexture();

     std.debug.assert(result == .success);
     const surface_texture = result.success;
     const view: wgpu.TextureView = try .init(
         surface_texture.texture,
         wgpu.TextureView.Descriptor{
             .label = "Surface texture view",
             .format = surface_texture.getFormat(),
             .dimension = .@"2d",
             .aspect = .all
         }
     );
     return view;
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

fn color(r: f64, g: f64, b: f64, a: f64) wgpu.Color {
    return .{
        .r = r,
        .g = g,
        .b = b,
        .a = a
    };
}
