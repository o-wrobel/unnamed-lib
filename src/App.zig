const std = @import("std");

const glfw = @import("glfw");
const Window = glfw.Window;
const wgpu = @import("wgpu");

const Vec2f = @Vector(2, f32);
const Color = @Vector(3, f32);

const uniform_stride = 256;

const Vertex = struct {
    const pos_format: wgpu.RenderPipeline.VertexFormat = .float32x2;
    const col_format: wgpu.RenderPipeline.VertexFormat = .float32x3;
    position: Vec2f,
    color: Color
};

const MyUniform = struct {
    time: f32 = 0,
    speed: f32 = 1,
    center: [2]f32 = .{0, 0},
};

const window_width = 640;
const window_height = 480;
const background_color: Color = .{0, 0, 0};

pub const App = @This();

const log = std.log.scoped(.App);

window: *Window,
device: wgpu.Device,
queue: wgpu.Queue,
surface: wgpu.Surface,
bind_group: wgpu.BindGroup,
render_pipeline: wgpu.RenderPipeline,

vertex_buffer: wgpu.Buffer,
vertex_count: u32,

index_buffer: wgpu.Buffer,
index_count: u32,

uniform_buffer: wgpu.Buffer,

pub fn init(allocator: std.mem.Allocator, io: std.Io) !App {
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
    defer adapter.deinit();
    printLimits(try adapter.getLimits());

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

    // Loading shader
    log.info("Loading shader", .{});
    const shader_module: wgpu.ShaderModule = init: {
        const shader_file = try std.Io.Dir.cwd().openFile(io, "my_shader.wgsl", .{});
        const sf_length = shader_file.length(io) catch unreachable;
        var sf_reader = shader_file.reader(io, &.{});
        const shader_text = try sf_reader.interface.allocRemaining(allocator, .limited64(sf_length+1));
        defer allocator.free(shader_text);
        const shader_source: wgpu.ShaderSource = .{ .wgsl = shader_text };
        break :init try .init(device.device, shader_source);
    };

    const uniform_buffer = init: {
        // const min_alignment = (try adapter.getLimits()).minUniformBufferOffsetAlignment;
        // const uniform_stride = ceilToNextMultiple(@sizeOf(MyUniform), min_alignment);
        // TODO: Figure this out instead of hard-coding

        const uniform_buffer = try device.createBuffer(.{
            .size = 2*uniform_stride,
            .usage = .{ .copy_dst = true, .uniform = true }
        });
        const value_1: MyUniform = .{
            .speed = 1
        };
        const value_2: MyUniform = .{
            .speed = 2,
            .center = .{1, 0}
        };
        queue.writeBuffer(MyUniform, uniform_buffer, 0, &.{ value_1 });
        queue.writeBuffer(MyUniform, uniform_buffer, uniform_stride, &.{ value_2 });
        break :init uniform_buffer;
    };

    const bind_group_layout = init: {
        const binding_layout: wgpu.BindGroupLayout.Entry = .{
            .binding = 0,
            .visibility = .{ .vertex = true },
            .buffer = .{
                .binding_type = .uniform,
                .min_binding_size = @sizeOf(MyUniform),
                .has_dynamic_offset = true
            },
        };
        break :init try device.createBindGroupLayout(.{ .entries = &.{ binding_layout }});
    };

    const bind_group = init: {
        const binding: wgpu.BindGroup.Entry = .{
            .binding = 0,
            .buffer = uniform_buffer,
            .offset = 0,
            .size = @sizeOf(MyUniform)
        };
        break :init try device.createBindGroup(.{
            .label = "My bind group",
            .layout = bind_group_layout,
            .entries = &.{ binding }
        });
    };

    const render_pipeline = init: {
        const blend_state: wgpu.RenderPipeline.BlendState = .{};
        const color_target: wgpu.RenderPipeline.ColorTargetState = .{
            .format = (try surface.getCapabilities(adapter.adapter)).formats[0],
            .blend = blend_state,
            .write_mask = .all
        };

        const position_attribute: wgpu.RenderPipeline.VertexAttribute = .{
            .shader_location = 0,
            .format = Vertex.pos_format,
            .offset = 0
        };
        const color_attribute: wgpu.RenderPipeline.VertexAttribute = .{
            .shader_location = 1,
            .format = Vertex.col_format,
            .offset = @sizeOf(Vec2f) // TODO: Replace this with @typeOf(position)
        };
        const vertex_buffer_layout: wgpu.RenderPipeline.VertexBufferLayout = .{
            .array_stride = @sizeOf(Vertex),
            .attributes = &.{ position_attribute, color_attribute },
        };

        const layout = try device.createPipelineLayout("My pipeline layout", &.{ bind_group_layout }, 0);

        break :init try device.createRenderPipeline(.{
            .label = "My render pipeline",
            .primitive = .{
                .topology = .triangle_list,
                .strip_index_format = .undefined,
                .front_face = .ccw,
                .cull_mode = .none
            },
            .vertex = .{
                .module = shader_module,
                .entry_point = "vs_main",
                .buffers = &.{ vertex_buffer_layout },
            },
            .fragment = .{
                .module = shader_module,
                .entry_point = "fs_main",
                .targets = &.{ color_target } // Only one target for only one output color attachment
            },
            .layout = layout,
            .depth_stencil = null,
        });
    };

    const vertex_buffer, const vertex_count: u32 = init: {
        const l = 0.3;
        const vertex_data = [_]Vertex{
            .{ .position = .{-l, -l}, .color = .{1, 0, 0} },
            .{ .position = .{l, -l}, .color = .{0, 1, 0} },
            .{ .position = .{l, l}, .color = .{0, 0, 1} },
            .{ .position = .{-l, l}, .color = .{1, 1, 0} },

        };
        const vertex_buffer = try device.createBuffer(.{
            .size = @sizeOf(@TypeOf(vertex_data)),
            .usage = .{ .copy_dst = true, .vertex = true }
        });
        queue.writeBuffer(Vertex, vertex_buffer, 0, &vertex_data);
        break :init .{ vertex_buffer, @intCast((&vertex_data).len) };
    };

    const index_buffer, const index_count: u32 = init: {
        const Index = u32;
        const index_data = [_]Index{
            0, 1, 2,
            0, 2, 3
        };
        const index_count: u32 = @intCast((&index_data).len);
        const index_buffer = try device.createBuffer(.{
            .size = index_count * @sizeOf(Index),
            .usage = .{ .copy_dst = true, .index = true }
        });
        queue.writeBuffer(Index, index_buffer, 0, &index_data);
        break :init .{ index_buffer, index_count };
    };

    return .{
        .window = window,
        .device = device,
        .queue = queue,
        .surface = surface,
        .bind_group = bind_group,
        .render_pipeline = render_pipeline,

        .vertex_buffer = vertex_buffer,
        .vertex_count = vertex_count,

        .index_buffer = index_buffer,
        .index_count = index_count,

        .uniform_buffer = uniform_buffer,
    };
}

pub fn deinit(self: App) void {
    log.info("Deinitializing", .{});
    self.device.deinit();
    self.queue.deinit();
    self.surface.deinit();
    self.window.destroy();
    self.bind_group.deinit();
    self.render_pipeline.deinit();

    self.vertex_buffer.deinit();
    self.index_buffer.deinit();
    self.uniform_buffer.deinit();
}

pub fn mainLoop(self: *const App) !void {
    log.info("Executing main loop", .{});
    while (true) {
        glfw.pollEvents();
        if (glfw.windowShouldClose(self.window)) break;
        const time: f32 = @floatCast(glfw.getTime());
        const uniform1: MyUniform = .{
            .time = time,
            .center = .{ -0.5, 0 },
            .speed = 1,
        };
        const uniform2: MyUniform = .{
            .time = time,
            .center = .{ 0.5, 0 },
            .speed = -1
        };
        self.queue.writeBuffer(MyUniform, self.uniform_buffer, 0, &.{ uniform1 });
        self.queue.writeBuffer(MyUniform, self.uniform_buffer, uniform_stride, &.{ uniform2 });

        const target_view = try getNextSurfaceTextureView(self.surface) orelse continue;
        const encoder = try self.device.createCommandEncoder(.{ .label = "My command encoder" });
        defer encoder.deinit();

        const color_attachment: wgpu.RenderPassEncoder.ColorAttachment = .{
            .view = target_view,
            .clear_value = color(background_color),
            .load_op = .clear,
            .store_op = .store,
        };

        const render_pass = try encoder.beginRenderPass(.{
            .color_attachments = &.{color_attachment},
            .label = "My render pass"
        });

        render_pass.setPipeline(self.render_pipeline);

        render_pass.setVertexBuffer(0, self.vertex_buffer, 0, self.vertex_buffer.size);
        render_pass.setIndexBuffer(self.index_buffer, .uint32, 0, self.index_buffer.size);

        render_pass.setBindGroup(0, self.bind_group, &.{ 0 });
        render_pass.drawIndexed(self.index_count, 1, 0, 0, 0);

        render_pass.setBindGroup(0, self.bind_group, &.{ @intCast(uniform_stride) });
        render_pass.drawIndexed(self.index_count, 1, 0, 0, 0);

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

fn getNextSurfaceTextureView(surface: wgpu.Surface) !?wgpu.TextureView {
     const result = surface.getCurrentTexture();

     const surface_texture = init: switch (result) {
         .success => {
             @branchHint(.likely);
             break :init result.success;
         },
         .suboptimal => { break :init result.suboptimal; },
         .timeout => { return null; },
         else => {
             @branchHint(.unlikely);
             std.debug.panic("Got surface texture result: {}", .{result});
         }
     };

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
            log.debug("{s}: {}", .{ f.name,  val});
        } else {
            log.debug("{s}: @{*}", .{ f.name,  val});
        }
    }
}

fn ceilToNextMultiple(value: usize, step: usize) usize {
    const add: usize = if (value % step == 0) 0 else 1;
    const divide_and_ceil: usize = value / step + add;
    return step * divide_and_ceil;
}

fn color(c: Color) wgpu.Color {
    return .{
        .r = c[0],
        .g = c[1],
        .b = c[2],
        .a = 1
    };
}
