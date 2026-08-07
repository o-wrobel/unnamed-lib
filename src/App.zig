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
render_pipeline: wgpu.RenderPipeline,
buffer1: wgpu.Buffer,
buffer2: wgpu.Buffer,

pub fn init(allocator: std.mem.Allocator, io: std.Io) !App {
    log.info("Initializing", .{});

    // Loading shader
    log.info("Loading shader", .{});
    const shader_file = try std.Io.Dir.cwd().openFile(io, "my_shader.wgsl", .{});
    const sf_length = shader_file.length(io) catch unreachable;
    var sf_reader = shader_file.reader(io, &.{});
    const shader_text = try sf_reader.interface.allocRemaining(allocator, .limited64(sf_length+1));
    defer allocator.free(shader_text);

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

    const device = try adapter.requestDeviceSync(.{
        .label = "My cool device",
        .queue_label = "Default queue"
    });
    // TODO: Set up callback functions

    const queue = try device.getQueue();

    const surface = init: {
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
        const surface_format = surface_capabilities.formats[0];

        surface.configure(.{
            .width = 400,
            .height = 400,
            .format = surface_format,
            .usage = .{ .render_attachment = true }, // The surface is a target for a render pass
            .device = device,
        });
        break :init surface;

    };

    const render_pipeline = init: {
        const shader_source: wgpu.ShaderSource = .{ .wgsl = shader_text };
        const shader_module: wgpu.ShaderModule = try .init(device.device, shader_source);

        const blend_state: wgpu.RenderPipeline.BlendState = .{};
        const color_target: wgpu.RenderPipeline.ColorTargetState = .{
            .format = (try surface.getCapabilities(adapter.adapter)).formats[0],
            .blend = blend_state,
            .write_mask = .all
        };
        break :init try device.createRenderPipeline(.{
            .primitive = .{
                .topology = .triangle_list,
                .strip_index_format = .undefined,
                .front_face = .ccw,
                .cull_mode = .none
            },
            .vertex = .{
                .module = shader_module,
                .entry_point = "vs_main",
                .buffers = &.{},
            },
            .fragment = .{
                .module = shader_module,
                .entry_point = "fs_main",
                .targets = &.{ color_target } // Only one target for only one output color attachment
            },
            .depth_stencil = null,
            .layout = null
        });
    };

    const buffer1: wgpu.Buffer, const buffer2: wgpu.Buffer = init: {
        const Context = struct {
            ready: bool,

            fn onBuffer2Mapped(status: wgpu.c.WGPUMapAsyncStatus, buffer: *const wgpu.Buffer, data: []const u8, user_data: ?*anyopaque) void {
                const context: *@This() = @alignCast(@ptrCast(user_data));
                _ = buffer;
                _ = data;
                log.debug("Buffer 2 mapped with status: {}", .{status});
                context.ready = true;
            }
        };

        const buffer1 = try device.createBuffer(.{
            .label = "Some GPU-side data buffer",
            .size = 16,
            .usage = .{ .copy_dst = true, .copy_src = true },
            .mapped_at_creation = false
        });
        const buffer2 = try device.createBuffer(.{
            .label = "Output buffer",
            .size = 16,
            .usage = .{ .copy_dst = true, .map_read = true },
            .mapped_at_creation = false
        });

        const numbers: [16]u8 = temp: {
            var arr: [16]u8 = undefined;
            for (0..16) |i| arr[i] = @intCast(i);
            break :temp arr;
        };
        queue.writeBuffer(u8, buffer1, 0, &numbers);

        const encoder = try device.createCommandEncoder(.{});
        defer encoder.deinit();

        encoder.copyBufferToBuffer(buffer1, 0, buffer2, 0, 16);

        // Submit the copy command FIRST, so the GPU executes it
        const command = try encoder.finish(.{});
        queue.submitCommands(&.{command});

        // Now map buffer2 to read back the result
        var context: Context = .{ .ready = false };
        try buffer2.mapAsync(.{ .read = true }, Context.onBuffer2Mapped, &context);
        while (!context.ready) _ = device.poll(false);

        // Read the mapped data
        const mapped = buffer2.getConstMappedRange(u8, 0, 16) orelse @panic("map failed");
        log.debug("Buffer2 data: {any}", .{mapped});
        buffer2.unmap();

        break :init .{ buffer1, buffer2 };

    };

    return .{
        .window = window,
        .device = device,
        .queue = queue,
        .surface = surface,
        .render_pipeline = render_pipeline,
        .buffer1 = buffer1,
        .buffer2 = buffer2
    };
}

pub fn deinit(self: App) void {
    log.info("Deinitializing", .{});
    self.device.deinit();
    self.queue.deinit();
    self.surface.deinit();
    self.window.destroy();
    self.render_pipeline.deinit();
    self.buffer1.deinit();
    self.buffer2.deinit();
}

pub fn mainLoop(self: *const App) !void {
    log.info("Executing main loop", .{});
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

        render_pass.setPipeline(self.render_pipeline);
        render_pass.draw(3, 1, 0, 0);

        render_pass.end();
        render_pass.deinit();

        const command = try encoder.finish(.{ .label = "Command buffer" });

        // std.log.debug("Submitting command...", .{});
        self.queue.submitCommands(&.{command});
        // std.log.debug("Command submitted", .{});

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
