const std = @import("std");

const glfw = @import("glfw");
const Window = glfw.Window;
const obj = @import("tinyobj");
const Scene = obj.Scene;
const wgpu = @import("wgpu");

pub const math = @import("math.zig");
const Mat4x4 = math.Mat4x4;
const identity_matrix = math.identity_matrix;
const ortho_projection = math.ortho_projection;
const transpose = math.transpose;
const rotationMatrix = math.rotationMatrix;
const batchMatrixMultiply = math.batchMatrixMultiply;
const modelTransform = math.modelTransform;
const viewTransform = math.viewTransform;
const projectionTransform = math.projectionTransform;
const Vec2f = math.Vec2f;
const Vec3f = math.Vec3f;

pub const Color = @Vector(3, f32);

const uniform_stride = 256;

pub const Vertex = struct {
    const pos_format: wgpu.RenderPipeline.VertexFormat = .float32x3;
    const norm_format: wgpu.RenderPipeline.VertexFormat = .float32x3;
    const col_format: wgpu.RenderPipeline.VertexFormat = .float32x3;
    const uv_format: wgpu.RenderPipeline.VertexFormat = .float32x2;
    position: Vec3f,
    normal: Vec3f,
    color: Color,
    uv: Vec2f,
};

const MyUniform = struct {
    model_tranform: Mat4x4 = identity_matrix,
    view_transform: Mat4x4 = identity_matrix,
    projection_transform: Mat4x4 = identity_matrix,
    time: f32 = 0,
    _pad: [3]f32 = @splat(0),
};

const window_width = 640;
const window_height = 480;
const background_color: Color = .{ 0.1, 0.1, 0.1 };

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

index_count: u32,

depth_texture: wgpu.Texture,
depth_texture_view: wgpu.TextureView,

pixel_image: [][4]u8,
texture: wgpu.Texture,

uniform_buffer: wgpu.Buffer,

pub fn init(model_filename: []const u8, allocator: std.mem.Allocator, io: std.Io) !App {
    log.info("Initializing", .{});

    log.info("Loading model file \"{s}\"", .{model_filename});
    const vertices = try loadOBJ(model_filename, allocator, io);
    defer allocator.free(vertices);

    // GLFW
    try glfw.init();

    glfw.windowHint(.client_api, .no_api);
    glfw.windowHint(.resizable, false);
    log.info("Creating window", .{});
    const window: *Window = try .create(
        window_width,
        window_height,
        "Hello, GLFW!",
        null,
        null,
    );

    // WGPU
    const instance = try wgpu.Instance.init(null);
    defer instance.deinit();

    const adapter = try instance.requestAdapterSync(.{});
    defer adapter.deinit();
    // printLimits(try adapter.getLimits());

    const device = try adapter.requestDeviceSync(.{
        .label = "My cool device",
        .queue_label = "Default queue",
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
            .width = window_width,
            .height = window_height,
            .format = surface_format,
            .usage = .{ .render_attachment = true }, // The surface is a target for a render pass
            .device = device,
        });
        break :init surface;
    };

    const texture = try device.createTexture(.{
        .size = .{ .width = 256, .height = 256 },
        .mip_level_count = 1,
        .sample_count = 1,
        .format = .rgba8_unorm,
        .usage = .{
            .copy_dst = true,
            .texture_binding = true,
        },
        .label = "My cool texture",
    });
    const texture_view = try texture.createView(.{
        .aspect = .all,
        .dimension = .@"2d",
        .format = texture.getFormat(),
    });

    const pixels = try textureImage(texture.getWidth(), texture.getHeight(), allocator);

    // Loading shader
    log.info("Loading shader", .{});
    const shader_module: wgpu.ShaderModule = init: {
        const shader_file = try std.Io.Dir.cwd().openFile(io, "my_shader.wgsl", .{});
        const sf_length = shader_file.length(io) catch unreachable;
        var sf_reader = shader_file.reader(io, &.{});
        const shader_text = try sf_reader.interface.allocRemaining(allocator, .limited64(sf_length + 1));
        defer allocator.free(shader_text);
        const shader_source: wgpu.ShaderSource = .{ .wgsl = shader_text };
        break :init try .init(device.device, shader_source);
    };

    const uniform_buffer = init: {
        // const min_alignment = (try adapter.getLimits()).minUniformBufferOffsetAlignment;
        // const uniform_stride = ceilToNextMultiple(@sizeOf(MyUniform), min_alignment);
        // TODO: Figure this out instead of hard-coding

        const uniform_buffer = try device.createBuffer(.{
            .size = 2 * uniform_stride,
            .usage = .{ .copy_dst = true, .uniform = true },
        });
        break :init uniform_buffer;
    };

    const uniform_binding_layout: wgpu.BindGroupLayout.Entry = .{
        .binding = 0,
        .visibility = .{ .vertex = true },
        .buffer = .{
            .binding_type = .uniform,
            .min_binding_size = @sizeOf(MyUniform),
            .has_dynamic_offset = true,
        },
    };
    const texture_binding_layout: wgpu.BindGroupLayout.Entry = .{
        .binding = 1,
        .visibility = .{ .fragment = true },
        .texture = .{ .sample_type = .float, .view_dimension = .@"2d" },
    };
    const bind_group_layout = try device.createBindGroupLayout(.{
        .entries = &.{ uniform_binding_layout, texture_binding_layout },
    });

    const bind_group = init: {
        const uniform_binding: wgpu.BindGroup.Entry = .{
            .binding = 0,
            .buffer = uniform_buffer,
            .offset = 0,
            .size = @sizeOf(MyUniform),
        };
        const texture_binding: wgpu.BindGroup.Entry = .{
            .binding = 1,
            .texture_view = texture_view,
        };
        break :init try device.createBindGroup(.{
            .label = "My bind group",
            .layout = bind_group_layout,
            .entries = &.{ uniform_binding, texture_binding },
        });
    };

    const render_pipeline = init: {
        const blend_state: wgpu.RenderPipeline.BlendState = .{};
        const color_target: wgpu.RenderPipeline.ColorTargetState = .{
            .format = (try surface.getCapabilities(adapter.adapter)).formats[0],
            .blend = blend_state,
            .write_mask = .all,
        };

        const position_attribute: wgpu.RenderPipeline.VertexAttribute = .{
            .shader_location = 0,
            .format = Vertex.pos_format,
            .offset = 0,
        };
        const normal_attribute: wgpu.RenderPipeline.VertexAttribute = .{
            .shader_location = 1,
            .format = Vertex.norm_format,
            .offset = 1 * @sizeOf(Vec3f),
        };
        const color_attribute: wgpu.RenderPipeline.VertexAttribute = .{
            .shader_location = 2,
            .format = Vertex.col_format,
            .offset = 2 * @sizeOf(Vec3f),
        };
        const uv_attribute: wgpu.RenderPipeline.VertexAttribute = .{
            .shader_location = 3,
            .format = Vertex.uv_format,
            .offset = 3 * @sizeOf(Vec3f),
        };
        const vertex_buffer_layout: wgpu.RenderPipeline.VertexBufferLayout = .{
            .array_stride = @sizeOf(Vertex),
            .attributes = &.{
                position_attribute,
                normal_attribute,
                color_attribute,
                uv_attribute,
            },
        };

        const layout = try device.createPipelineLayout("My pipeline layout", &.{bind_group_layout}, 0);

        break :init try device.createRenderPipeline(.{
            .label = "My render pipeline",
            .primitive = .{
                .topology = .triangle_list,
                .strip_index_format = .undefined,
                .front_face = .ccw,
                .cull_mode = .none,
            },
            .vertex = .{
                .module = shader_module,
                .entry_point = "vs_main",
                .buffers = &.{vertex_buffer_layout},
            },
            .fragment = .{
                .module = shader_module,
                .entry_point = "fs_main",
                .targets = &.{color_target}, // Only one target for only one output color attachment
            },
            .layout = layout,
            .depth_stencil = .{
                .depth_compare = .less,
                .depth_write_enabled = true,
                .format = .depth24_plus,
                .stencil_read_mask = 0,
                .stencil_write_mask = 0,
            },
        });
    };

    const vertex_buffer, const vertex_count: u32 = init: {
        const vertex_buffer = try device.createBuffer(.{
            .size = vertices.len * @sizeOf(Vertex),
            .usage = .{ .copy_dst = true, .vertex = true },
        });
        queue.writeBuffer(Vertex, vertex_buffer, 0, vertices);
        break :init .{ vertex_buffer, @intCast(vertices.len) };
    };

    const depth_texture = try device.createTexture(.{
        .usage = .{ .render_attachment = true },
        .dimension = .@"2d",
        .format = .depth24_plus,
        .size = .{
            .width = window_width,
            .height = window_height,
        },
    });
    const depth_texture_view = try depth_texture.createView(.{
        .aspect = .depth_only,
        .dimension = .@"2d",
        .format = .depth24_plus,
    });

    const destination: wgpu.Queue.TexelCopyTextureInfo = .{
        .texture = texture,
        .aspect = .all,
    };
    queue.writeTexture(
        [4]u8,
        destination,
        pixels,
        .{
            .bytes_per_row = 4 * texture.getWidth(),
            .rows_per_image = texture.getHeight(),
        },
        .{
            .width = texture.getWidth(),
            .height = texture.getHeight(),
        },
    );

    return .{
        .window = window,
        .device = device,
        .queue = queue,
        .surface = surface,
        .bind_group = bind_group,
        .render_pipeline = render_pipeline,

        .vertex_buffer = vertex_buffer,
        .vertex_count = vertex_count,

        .index_count = @intCast(vertices.len),

        .depth_texture = depth_texture,
        .depth_texture_view = depth_texture_view,

        .pixel_image = pixels,
        .texture = texture,

        .uniform_buffer = uniform_buffer,
    };
}

pub fn deinit(self: App, allocator: std.mem.Allocator) void {
    log.info("Deinitializing", .{});
    self.device.deinit();
    self.queue.deinit();
    self.surface.deinit();
    self.window.destroy();
    self.bind_group.deinit();
    self.render_pipeline.deinit();

    allocator.free(self.pixel_image);

    self.vertex_buffer.deinit();
    self.uniform_buffer.deinit();
}

pub fn mainLoop(self: *const App) !void {
    log.info("Executing main loop", .{});
    while (true) {
        glfw.pollEvents();
        if (glfw.windowShouldClose(self.window)) break;
        const time: f32 = @floatCast(glfw.getTime());

        const model_transform = modelTransform(
            0.3,
            .{ 0, 0, 0 },
            .{ .roll = time },
        );
        const view_transform = viewTransform(
            .{ 0, 0, -1 },
            .{ .pitch = std.math.degreesToRadians(115) },
        );
        const projection_transform = projectionTransform(
            640.0 / 480.0,
            std.math.degreesToRadians(60),
        );

        // const model_transform = identity_matrix;
        // const view_transform = identity_matrix;
        // const projection_transform = ortho_projection;

        const uniform1: MyUniform = .{
            .time = time,
            .model_tranform = model_transform,
            .view_transform = view_transform,
            .projection_transform = projection_transform,
        };
        self.queue.writeBuffer(MyUniform, self.uniform_buffer, 0, &.{uniform1});
        // self.queue.writeBuffer(MyUniform, self.uniform_buffer, uniform_stride, &.{ uniform2 });

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
            .label = "My render pass",
            .depth_stencil_attachment = .{
                .view = self.depth_texture_view,
                .depth_clear_value = 1,
                .depth_load_op = .clear,
                .depth_store_op = .store,
                .depth_read_only = false,
            },
        });

        render_pass.setPipeline(self.render_pipeline);

        render_pass.setVertexBuffer(0, self.vertex_buffer, 0, self.vertex_buffer.size);

        render_pass.setBindGroup(0, self.bind_group, &.{0});
        render_pass.draw(self.vertex_count, 1, 0, 0);

        render_pass.end();
        render_pass.deinit();

        const command = try encoder.finish(.{ .label = "Command buffer" });

        self.queue.submitCommands(&.{command});

        try self.surface.present();

        target_view.deinit();
        _ = self.device.poll(false);
    }
}

// Utility functions

fn textureImage(width: usize, height: usize, allocator: std.mem.Allocator) ![][4]u8 {
    return init: {
        const pixels = try allocator.alloc([4]u8, width * height);
        for (0..width) |i| {
            for (0..height) |j| {
                const i_s: i32 = @intCast(i);
                const j_s: i32 = @intCast(j);

                const red: u8 = if (@mod((@divTrunc(i_s, 16)), 2) == @mod((@divTrunc(j_s, 16)), 2)) 255 else 0;
                const green: u8 = if (@mod((@divTrunc(i_s - j_s, 16)), 2) == 0) 255 else 0;
                const blue: u8 = if (@mod((@divTrunc(i_s + j_s, 16)), 2) == 0) 255 else 0;
                const alpha: u8 = 255;

                pixels[j * width + i] = .{ red, green, blue, alpha };
            }
        }
        break :init pixels;
    };
}

pub fn loadOBJ(filename: []const u8, allocator: std.mem.Allocator, io: std.Io) ![]Vertex {
    const model_file = try std.Io.Dir.cwd().openFile(io, filename, .{});
    const file_len = model_file.length(io) catch unreachable;
    var file_reader = model_file.reader(io, &.{});
    const text = try file_reader.interface.allocRemaining(allocator, .limited64(file_len + 1));
    defer allocator.free(text);

    const scene = try obj.loadFromMemory(text, .{});
    const shape = (scene.shapes orelse unreachable)[0];
    const vertices = try allocator.alloc(Vertex, @intCast(shape.mesh.num_indices));

    for (0..shape.mesh.num_indices) |i| {
        const index = shape.mesh.indices[i];
        const vi: usize = @intCast(index.vertex_index);
        const ni: usize = @intCast(index.normal_index);
        const ti: usize = @intCast(index.texcoord_index);
        vertices[i] = Vertex{
            .position = .{
                scene.attributes.vertices.ptr[3 * vi + 0],
                -scene.attributes.vertices.ptr[3 * vi + 2], // Assuming Y represents up
                scene.attributes.vertices.ptr[3 * vi + 1],
            },
            .normal = .{
                scene.attributes.normals.ptr[3 * ni + 0],
                -scene.attributes.normals.ptr[3 * ni + 2], // Assuming Y represents up
                scene.attributes.normals.ptr[3 * ni + 1],
            },
            .color = .{
                scene.attributes.colors.ptr[3 * vi + 0],
                scene.attributes.colors.ptr[3 * vi + 1],
                scene.attributes.colors.ptr[3 * vi + 2],
            },
            .uv = .{
                scene.attributes.texcoords.ptr[2 * ti + 0],
                1 - scene.attributes.texcoords.ptr[2 * ti + 1],
            },
        };
    }

    return vertices;
}

fn getNextSurfaceTextureView(surface: wgpu.Surface) !?wgpu.TextureView {
    const result = surface.getCurrentTexture();

    const surface_texture = init: switch (result) {
        .success => {
            @branchHint(.likely);
            break :init result.success;
        },
        .suboptimal => {
            break :init result.suboptimal;
        },
        .timeout => {
            return null;
        },
        else => {
            @branchHint(.unlikely);
            std.debug.panic("Got surface texture result: {}", .{result});
        },
    };
    return try wgpu.TextureView.init(
        surface_texture.texture,
        wgpu.TextureView.Descriptor{
            .label = "Surface texture view",
            .format = surface_texture.getFormat(),
            .dimension = .@"2d",
            .aspect = .all,
        },
    );
}

fn color(c: Color) wgpu.Color {
    return .{ .r = c[0], .g = c[1], .b = c[2], .a = 1 };
}
