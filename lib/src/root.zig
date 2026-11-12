const std = @import("std");

const glfw = @import("glfw");
const Window = glfw.Window;
const obj = @import("tinyobj");
const Scene = obj.Scene;
const wgpu = @import("wgpu");

pub const Input = @import("Input.zig");
pub const math = @import("math.zig");
const Mat4x4 = math.Mat4x4;
const identity_matrix = math.identity_matrix;
const ortho_projection = math.ortho_projection;
const transpose = math.transpose;
const rotationMatrix = math.rotationMatrix;
const batchMatrixMultiply = math.batchMatrixMultiply;
pub const modelTransform = math.modelTransform;
pub const viewTransform = math.viewTransform;
pub const projectionTransform = math.projectionTransform;
pub const Vec2f = math.Vec2f;
pub const Vec3f = math.Vec3f;

pub const Color = @Vector(3, f32);
pub const Image = struct {
    pixels: [][4]u8,
    width: usize,
    height: usize,

    pub fn deinit(self: Image, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
    }
};

const default_shader_data = @embedFile("default.wgsl");

const uniform_stride = 256;

pub const Vertex = struct {
    position: Vec3f,
    normal: Vec3f,
    color: Color,
    uv: Vec2f,
    pub const buffer_layout = bufferLayout(@This());
};

pub const MyUniform = struct {
    model_tranform: Mat4x4 = identity_matrix,
    view_transform: Mat4x4 = identity_matrix,
    projection_transform: Mat4x4 = identity_matrix,
    time: f32 = 0,
    _pad: [3]f32 = @splat(0),
};

const window_width = 640;
const window_height = 480;
const background_color: Color = .{ 0.1, 0.1, 0.1 };

pub const Device = @This();
const log = std.log.scoped(.UnnamedLib);

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

texture: wgpu.Texture,

uniform_buffer: wgpu.Buffer,

// User-space values
input: Input,
should_close: bool = false,
time: f32 = 0,
delta_time: f32 = 0,

pub fn init(
    model_filename: []const u8,
    comptime input_options: Input.Options,
    allocator: std.mem.Allocator,
    io: std.Io,
) !Device {
    const parent_progress_node = std.Progress.start(io, .{ .root_name = "Initializing" });
    defer parent_progress_node.end();
    defer log.info("Initialization finished", .{});

    const model_loading_node = parent_progress_node.start("Loading model", 0);
    const vertices = try loadOBJ(model_filename, allocator, io);
    defer allocator.free(vertices);
    model_loading_node.end();
    log.info("Model loaded: \x1B[34m{s}", .{model_filename});

    const image_node = parent_progress_node.start("Creating image", 0);
    const image = try createImage(256, 256, allocator);
    defer allocator.free(image.pixels);
    image_node.end();
    log.info("Image created", .{});

    // GLFW
    const window_node = parent_progress_node.start("Creating window", 2);
    try glfw.init();
    window_node.completeOne();
    glfw.windowHint(.client_api, .no_api);
    glfw.windowHint(.resizable, false);
    const window: *Window = try .create(
        window_width,
        window_height,
        "Hello, GLFW!",
        null,
        null,
    );
    window_node.end();
    log.info("Window created", .{});

    const input = try Input.init(input_options, window);

    // WGPU
    const wgpu_node = parent_progress_node.start("Setting up WebGPU", 0);
    const instance = try wgpu.Instance.init(null);
    defer instance.deinit();
    wgpu_node.completeOne();

    const adapter = try instance.requestAdapterSync(.{});
    defer adapter.deinit();
    wgpu_node.completeOne();

    const device = try adapter.requestDeviceSync(.{
        .label = "My cool device",
        .queue_label = "Default queue",
    });
    // TODO: Set up callback functions
    wgpu_node.completeOne();

    const queue = try device.getQueue();
    wgpu_node.completeOne();

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
    wgpu_node.completeOne();

    const shader_module: wgpu.ShaderModule = try .init(device.device, .{ .wgsl = default_shader_data });
    wgpu_node.completeOne();
    log.info("Default shader loaded", .{});

    const texture_node = wgpu_node.start("Setting up textures", 4);
    const mip_level_count: u32 = 8;
    const texture = try device.createTexture(.{
        .size = .{
            .width = @intCast(image.width),
            .height = @intCast(image.height),
        },
        .mip_level_count = mip_level_count,
        .sample_count = 1,
        .format = .rgba8_unorm,
        .usage = .{
            .copy_dst = true,
            .texture_binding = true,
        },
        .label = "My cool texture",
    });
    texture_node.completeOne();
    const texture_view = try texture.createView(.{
        .aspect = .all,
        .dimension = .@"2d",
        .format = texture.getFormat(),
        .mip_level_count = mip_level_count,
    });
    texture_node.completeOne();
    const sampler = try device.createSampler(.{
        .label = "My sampler",

        // Address modes specify how the texture is
        // supposed to be displayed out of its bounds
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,

        .mag_filter = .linear,
        .min_filter = .linear,
        .mipmap_filter = .linear,
        .lod_min_clamp = 0,
        .lod_max_clamp = mip_level_count,
        .compare = .undefined,
        .max_anisotropy = 1,
    });
    texture_node.completeOne();
    texture_node.end();
    wgpu_node.completeOne();
    log.info("Texture created", .{});

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
    wgpu_node.completeOne();
    log.info("Depth texture created", .{});

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

    // Binding

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
    const sampler_binding_layout: wgpu.BindGroupLayout.Entry = .{
        .binding = 2,
        .visibility = .{ .fragment = true },
        .sampler = .{ .binding_type = .filtering },
    };
    const bind_group_layout = try device.createBindGroupLayout(.{
        .entries = &.{
            uniform_binding_layout,
            texture_binding_layout,
            sampler_binding_layout,
        },
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
        const sampler_binding: wgpu.BindGroup.Entry = .{
            .binding = 2,
            .sampler = sampler,
        };
        break :init try device.createBindGroup(.{
            .label = "My bind group",
            .layout = bind_group_layout,
            .entries = &.{
                uniform_binding,
                texture_binding,
                sampler_binding,
            },
        });
    };
    wgpu_node.completeOne();
    log.info("Bind group created", .{});

    const render_pipeline = init: {
        const blend_state: wgpu.RenderPipeline.BlendState = .{};
        const color_target: wgpu.RenderPipeline.ColorTargetState = .{
            .format = (try surface.getCapabilities(adapter.adapter)).formats[0],
            .blend = blend_state,
            .write_mask = .all,
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
                .buffers = &.{Vertex.buffer_layout},
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
    wgpu_node.completeOne();
    log.info("Render pipeline created", .{});

    const vertex_buffer, const vertex_count: u32 = init: {
        const vertex_buffer = try device.createBuffer(.{
            .size = vertices.len * @sizeOf(Vertex),
            .usage = .{ .copy_dst = true, .vertex = true },
        });
        queue.writeBuffer(Vertex, vertex_buffer, 0, vertices);
        break :init .{ vertex_buffer, @intCast(vertices.len) };
    };
    wgpu_node.completeOne();
    log.info("Vertex buffer created", .{});

    // Create and upload texture data, one mip level at a time. Each mip level
    // is generated by downsampling the previous one, which is what
    // `createMipMap` expects (the source is exactly 2x the destination size).
    var previous_image: Image = image;
    for (0..mip_level_count) |level| {
        const destination: wgpu.Queue.TexelCopyTextureInfo = .{
            .texture = texture,
            .aspect = .all,
            .mip_level = @intCast(level),
        };
        const mip_level_size: wgpu.types.Extent3D = .{
            .width = texture.getWidth() / std.math.pow(u32, 2, @intCast(level)),
            .height = texture.getHeight() / std.math.pow(u32, 2, @intCast(level)),
        };
        const source: wgpu.types.TexelCopyBufferLayout = .{
            .bytes_per_row = 4 * mip_level_size.width,
            .rows_per_image = mip_level_size.height,
        };
        const image_to_upload = if (level == 0) image else try createMipMap(previous_image, allocator);

        queue.writeTexture(
            [4]u8,
            destination,
            image_to_upload.pixels,
            source,
            mip_level_size,
        );

        if (level != 0) {
            if (level != 1) previous_image.deinit(allocator);
            previous_image = image_to_upload;
        }
    }
    if (mip_level_count > 1) previous_image.deinit(allocator);
    wgpu_node.completeOne();
    log.info("Mip maps created", .{});
    wgpu_node.end();

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
        .texture = texture,
        .uniform_buffer = uniform_buffer,
        .input = input,
    };
}

pub fn deinit(self: Device) void {
    log.info("Deinitializing", .{});
    self.device.deinit();
    self.queue.deinit();
    self.surface.deinit();
    self.window.destroy();
    self.bind_group.deinit();
    self.render_pipeline.deinit();

    self.vertex_buffer.deinit();
    self.uniform_buffer.deinit();
}

pub fn tick(self: *Device, uniform: MyUniform) !void {
    glfw.pollEvents();
    self.should_close = glfw.windowShouldClose(self.window);
    self.delta_time = @floatCast(glfw.getTime() - self.time);
    self.time = @floatCast(glfw.getTime());

    self.queue.writeBuffer(MyUniform, self.uniform_buffer, 0, &.{uniform});

    const target_view = try getNextSurfaceTextureView(self.surface) orelse unreachable;
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

// Utility functions

pub fn bufferLayout(comptime T: type) wgpu.RenderPipeline.VertexBufferLayout {
    const ti = @typeInfo(T);
    const s = ti.@"struct";
    const types = s.field_types;
    const attributes: [types.len]wgpu.RenderPipeline.VertexAttribute = blk: {
        var result: [types.len]wgpu.RenderPipeline.VertexAttribute = undefined;
        var offset: u32 = 0;
        var location: u32 = 0;
        for (types) |K| {
            const format = formatFromType(K);
            const size = @sizeOf(K);
            result[location] = .{
                .format = format,
                .offset = offset,
                .shader_location = location,
            };
            offset += size;
            location += 1;
        }
        break :blk result;
    };
    return .{
        .attributes = &attributes,
        .array_stride = @sizeOf(T),
    };
}

fn formatFromType(comptime T: type) wgpu.RenderPipeline.VertexFormat {
    var type_name: []const u8 = undefined;
    var type_size_bits: u32 = undefined;
    return switch (@typeInfo(T)) {
        .vector => |V| blk: {
            switch (@typeInfo(V.child)) {
                .float => |F| {
                    type_name = "float";
                    type_size_bits = F.bits;
                },
                else => @compileError("Unimplemented for non-float vectors"),
            }
            const format_name = std.fmt.comptimePrint("{s}{d}x{d}", .{ type_name, type_size_bits, V.len });
            break :blk @field(wgpu.RenderPipeline.VertexFormat, format_name);
        },
        else => @compileError("Unimplemented for non-float vectors"),
    };
}

fn createImage(width: usize, height: usize, allocator: std.mem.Allocator) !Image {
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
    return .{ .pixels = pixels, .width = width, .height = height };
}

fn createMipMap(previous_image: Image, allocator: std.mem.Allocator) !Image {
    const width = previous_image.width / 2;
    const height = previous_image.height / 2;
    const pixels = try allocator.alloc([4]u8, width * height);
    for (0..height) |j| {
        for (0..width) |i| {
            const p_00: @Vector(4, u32) = previous_image.pixels[previous_image.width * (2 * j) + (2 * i)];
            const p_01: @Vector(4, u32) = previous_image.pixels[previous_image.width * (2 * j) + (2 * i + 1)];
            const p_10: @Vector(4, u32) = previous_image.pixels[previous_image.width * (2 * j + 1) + (2 * i)];
            const p_11: @Vector(4, u32) = previous_image.pixels[previous_image.width * (2 * j + 1) + (2 * i + 1)];
            const avg: @Vector(4, u8) = @intCast((p_00 + p_01 + p_10 + p_11) / @as(@Vector(4, u32), @splat(4)));
            var rgba: [4]u8 = avg;
            rgba[3] = 255;
            pixels[j * width + i] = rgba;
        }
    }
    return .{ .pixels = pixels, .width = width, .height = height };
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
