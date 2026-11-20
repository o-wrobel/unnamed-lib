const std = @import("std");

const glfw = @import("glfw");
pub const Window = glfw.Window;
const obj = @import("tinyobj");
const stbi = @import("stbi");
const wgpu = @import("wgpu");

const math = @import("math.zig");
const Rotation = math.Rotation;
const Mat4x4 = math.Mat4x4;
const identity_matrix = math.identity_matrix;
const modelTransform = math.modelTransform;
const projectionTransform = math.projectionTransform;
const Vec2f = math.Vec2f;
const Vec3f = math.Vec3f;

const log = std.log.scoped(.UnnamedLib);

pub const Camera = @import("Camera.zig");

pub const SceneOptions = struct {
    pub const Model = struct {
        scale: f32 = 1,
        translation: Vec3f = @splat(0),
        rotation_along_origin: Rotation = .{},
    };
    pub const Projection = struct {
        /// In radians
        vertical_field_of_view: f32,
    };
    pub const Lighting = struct {
        directions: [2]Vec3f = .{ .{ 1.0, -0.9, 0.1 }, .{ 0.2, 0.4, 0.3 } },
        colors: [2]Vec3f = .{ .{ 1, 0.9, 0.8 }, .{ 1, 0.4, 0.1 } },
        hardness: f32 = 2,
        diffuse_strength: f32 = 1,
        specular_strength: f32 = 0.5,
    };
    model_transform: Model,
    projection_transform: Projection,
    camera: Camera,
    lighting: Lighting = .{},
};

pub const MyUniform = extern struct {
    model_tranform: Mat4x4 align(16) = identity_matrix,
    view_transform: Mat4x4 align(16) = identity_matrix,
    projection_transform: Mat4x4 align(16) = identity_matrix,
    camera_world_position: [3]f32,
    time: f32 align(16) = 0,

    pub fn stride() comptime_int {
        return @sizeOf(@This());
    }
};

pub const LightingUniform = extern struct {
    directions: [2][4]f32 align(16),
    colors: [2][4]f32 align(16),
    hardness: f32 = 2,
    diffuse_strength: f32 = 1,
    specular_strength: f32 = 0.5,
};

const uniform_stride = MyUniform.stride();
const background_color: Color = .{ 0.1, 0.1, 0.1 };

const default_shader_data = @embedFile("default.wgsl");

/// Optional per-frame hook: invoked inside the render pass, right before it
/// ends, so callers can draw UI (ImGui, debug overlays, ...) without the
/// engine depending on any GUI library. `pass` is the raw
/// WGPURenderPassEncoder, and `width`/`height` are the actual render-target
/// size for this frame (they can differ from the window size right after a
/// resize), so UI libraries must use them instead of re-querying the window.
pub const UiDraw = struct {
    context: ?*anyopaque = null,
    draw: *const fn (?*anyopaque, *anyopaque, u32, u32) void,
};

pub const Core = @This();
window: *Window,
allocator: std.mem.Allocator,
device: wgpu.Device,
queue: wgpu.Queue,
surface: wgpu.Surface,
surface_format: wgpu.Texture.Format,
bind_group: wgpu.BindGroup,
render_pipeline: wgpu.RenderPipeline,

vertex_buffer: wgpu.Buffer,
vertex_count: u32,

index_count: u32,

depth_texture: wgpu.Texture,
depth_texture_view: wgpu.TextureView,

texture: wgpu.Texture,

normal_texture: wgpu.Texture,

uniform_buffer: wgpu.Buffer,
lighting_uniform_buffer: wgpu.Buffer,

pub fn init(
    model_filename: []const u8,
    texture_filename: []const u8,
    window_width: u32,
    window_height: u32,
    allocator: std.mem.Allocator,
    io: std.Io,
) !*Core {
    const parent_progress_node = std.Progress.start(io, .{ .root_name = "Initializing" });
    defer log.info("Initialization finished", .{});

    defer parent_progress_node.end();

    const core = try allocator.create(Core);
    errdefer allocator.destroy(core);

    try stbi.init(allocator);

    const instance = try wgpu.Instance.init(null);
    defer instance.deinit();

    const adapter = try instance.requestAdapterSync(.{});
    defer adapter.deinit();

    const device = try adapter.requestDeviceSync(.{
        .label = "My device",
        .uncaptured_error_callback = onUncapturedError,
    });
    var init_gpu_future = try io.concurrent(initGpu, .{
        texture_filename,
        window_width,
        window_height,
        device,
        allocator,
    });

    const vertices = try loadOBJ(model_filename, allocator, io);
    defer allocator.free(vertices);
    log.info("Model loaded: \x1B[34m{s}", .{model_filename});

    log.info("Initializing GLFW", .{});
    try glfw.init();
    glfw.windowHint(.client_api, .no_api);
    glfw.windowHint(.resizable, true);
    const window: *Window = try .create(
        @intCast(window_width),
        @intCast(window_height),
        "Hello, GLFW!",
        null,
        null,
    );
    log.info("Window created", .{});

    // After initGpu is finished:
    const result = try init_gpu_future.await(io);
    const texture = result.texture.@"0";
    const depth_texture, const depth_texture_view = result.depth;
    const queue = result.queue;
    const bind_group = result.bind_group;
    const bind_group_layout = result.bind_group_layout;
    const shader_module = result.shader;
    const uniform_buffer = result.uniform_buffer;
    const lighting_uniform_buffer = result.lighting_uniform_buffer;

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

    var surface = try instance.createSurface(&surface_desc);

    const surface_capabilities = try surface.getCapabilities(adapter.adapter);
    const surface_format = surface_capabilities.formats[0];

    const window_size = window.getFramebufferSize();
    surface.configure(.{
        .width = @intCast(window_size[0]),
        .height = @intCast(window_size[1]),
        .format = surface_format,
        .usage = .{ .render_attachment = true }, // The surface is a target for a render pass
        .device = device,
    });
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
    log.info("Render pipeline created", .{});

    const vertex_buffer, const vertex_count: u32 = init: {
        const vertex_buffer = try device.createBuffer(.{
            .size = vertices.len * @sizeOf(Vertex),
            .usage = .{ .copy_dst = true, .vertex = true },
        });
        queue.writeBuffer(Vertex, vertex_buffer, 0, vertices);
        break :init .{ vertex_buffer, @intCast(vertices.len) };
    };
    log.info("Vertex buffer created", .{});

    core.* = .{
        .window = window,
        .allocator = allocator,
        .device = device,
        .queue = queue,
        .surface = surface,
        .surface_format = surface_format,
        .bind_group = bind_group,
        .render_pipeline = render_pipeline,
        .vertex_buffer = vertex_buffer,
        .vertex_count = vertex_count,
        .index_count = @intCast(vertices.len),

        .texture = texture,
        .depth_texture = depth_texture,
        .depth_texture_view = depth_texture_view,
        .normal_texture = result.normal_texture,

        .uniform_buffer = uniform_buffer,
        .lighting_uniform_buffer = lighting_uniform_buffer,
    };

    // Hand the heap-allocated Device to GLFW so callbacks can reach it.
    window.setUserPointer(core);
    _ = window.setFramebufferSizeCallback(&onWindowResizeCallback);

    // The depth texture was created on the worker with the *requested* size;
    // the actual framebuffer can differ (HiDPI). The depth attachment must
    // match the surface size, so recreate it when they disagree.
    const framebuffer_w: u32 = @intCast(window_size[0]);
    const framebuffer_h: u32 = @intCast(window_size[1]);
    if (framebuffer_w != window_width or framebuffer_h != window_height)
        resizeWindow(core, framebuffer_w, framebuffer_h);

    return core;
}

pub fn deinit(self: *Core) void {
    self.device.deinit();
    self.queue.deinit();
    self.surface.deinit();
    self.window.destroy();
    self.bind_group.deinit();
    self.render_pipeline.deinit();

    self.vertex_buffer.deinit();
    self.uniform_buffer.deinit();

    self.texture.deinit();
    self.depth_texture.deinit();
    self.depth_texture_view.deinit();

    stbi.deinit();
    self.allocator.destroy(self);
}

pub fn tick(core: *Core, scene_options: SceneOptions, ui_draw: ?UiDraw) !void {
    glfw.pollEvents();

    // The resize callback fires during pollEvents and updates
    // core.width/height, so the aspect ratio is fresh every frame.
    const window_width_f: f32 = @floatFromInt(core.window.getSize()[0]);
    const window_height_f: f32 = @floatFromInt(core.window.getSize()[1]);
    const aspect_ratio = window_width_f / window_height_f;
    const projection_transform = projectionTransform(
        aspect_ratio,
        scene_options.projection_transform.vertical_field_of_view,
    );
    const uniform: MyUniform = .{
        .model_tranform = modelTransform(
            scene_options.model_transform.scale,
            scene_options.model_transform.translation,
            scene_options.model_transform.rotation_along_origin,
        ),
        .view_transform = scene_options.camera.viewTransform(),
        .camera_world_position = scene_options.camera.position(),
        .projection_transform = projection_transform,
    };
    core.queue.writeBuffer(MyUniform, core.uniform_buffer, 0, &.{uniform});

    const lighting_uniform: LightingUniform = .{
        .directions = .{
            vec4(scene_options.lighting.directions[0], 0),
            vec4(scene_options.lighting.directions[1], 0),
        },
        .colors = .{
            vec4(scene_options.lighting.colors[0], 1),
            vec4(scene_options.lighting.colors[1], 1),
        },
        .hardness = scene_options.lighting.hardness,
        .diffuse_strength = scene_options.lighting.diffuse_strength,
        .specular_strength = scene_options.lighting.specular_strength,
    };
    core.queue.writeBuffer(
        LightingUniform,
        core.lighting_uniform_buffer,
        0,
        &.{lighting_uniform},
    );

    const target = try getNextSurfaceTextureView(core.surface) orelse return;
    const encoder = try core.device.createCommandEncoder(.{ .label = "My command encoder" });
    defer encoder.deinit();

    const color_attachment: wgpu.RenderPassEncoder.ColorAttachment = .{
        .view = target.view,
        .clear_value = color(background_color),
        .load_op = .clear,
        .store_op = .store,
    };

    const render_pass = try encoder.beginRenderPass(.{
        .color_attachments = &.{color_attachment},
        .label = "My render pass",
        .depth_stencil_attachment = .{
            .view = core.depth_texture_view,
            .depth_clear_value = 1,
            .depth_load_op = .clear,
            .depth_store_op = .store,
            .depth_read_only = false,
        },
    });

    render_pass.setPipeline(core.render_pipeline);

    render_pass.setVertexBuffer(0, core.vertex_buffer, 0, core.vertex_buffer.size);

    render_pass.setBindGroup(0, core.bind_group, &.{0});
    render_pass.draw(core.vertex_count, 1, 0, 0);

    // Let the caller draw its UI inside this pass. Pass the actual target size:
    // after a resize the window may report a size that does not match the
    // surface texture we are rendering into yet.
    if (ui_draw) |ui| ui.draw(ui.context, render_pass.encoder, target.width, target.height);

    render_pass.end();
    render_pass.deinit();

    const command = try encoder.finish(.{ .label = "Command buffer" });

    core.queue.submitCommands(&.{command});

    try core.surface.present();

    target.view.deinit();
    _ = core.device.poll(false);
}

pub const Color = @Vector(3, f32);
pub const Image = struct {
    pixels: [][4]u8,
    width: usize,
    height: usize,

    pub fn deinit(self: Image, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
    }
};
pub const Vertex = struct {
    position: Vec3f,

    tangent: Vec3f,
    bitangent: Vec3f,
    normal: Vec3f,

    color: Color,
    uv: Vec2f,
    pub const buffer_layout = bufferLayout(@This());
};
const TextureAndView = struct { wgpu.Texture, wgpu.TextureView };
const GpuState = struct {
    queue: wgpu.Queue,

    texture: TextureAndView,
    normal_texture: wgpu.Texture,
    depth: TextureAndView,

    bind_group: wgpu.BindGroup,
    bind_group_layout: wgpu.BindGroupLayout,

    shader: wgpu.ShaderModule,
    uniform_buffer: wgpu.Buffer,
    lighting_uniform_buffer: wgpu.Buffer,
};

fn initGpu(
    texture_filename: []const u8,
    window_width: u32,
    window_height: u32,
    device: wgpu.Device,
    allocator: std.mem.Allocator,
) !GpuState {
    const queue = try device.getQueue();

    const uniform_buffer = try device.createBuffer(.{
        .size = 2 * uniform_stride,
        .usage = .{ .copy_dst = true, .uniform = true },
    });

    const lighting_uniform_buffer = init: {
        const lighting_uniform_buffer = try device.createBuffer(.{
            .size = 2 * uniform_stride,
            .usage = .{ .copy_dst = true, .uniform = true },
        });
        break :init lighting_uniform_buffer;
    };

    const shader_module: wgpu.ShaderModule = try .init(device.device, .{ .wgsl = default_shader_data });
    log.info("Default shader loaded", .{});

    const mip_level_count: u32 = 6;
    const texture, const texture_view = try loadTextureFromFile(texture_filename, mip_level_count, device, allocator);
    log.info("Texture loaded: \x1B[34m{s}", .{texture_filename});

    const normal_texture_filename = "normals.jpg";
    const normal_texture, const normal_texture_view = try loadTextureFromFile("normals.jpg", mip_level_count, device, allocator);
    log.info("Normal map loaded: \x1B[34m{s}\x1B[0m", .{normal_texture_filename});

    const depth_texture, const depth_texture_view = try initDepthTexture(window_width, window_height, device);

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

    // Binding
    const bind_group_thing: BindGroup.Layout = .{
        .entries = &.{
            // Uniform
            .{
                .visibility = .{ .vertex = true },
                .resource = .{
                    .buffer = .{
                        .binding_type = .uniform,
                        .min_binding_size = @sizeOf(MyUniform),
                        .has_dynamic_offset = true,
                    },
                },
            },
            // Texture
            .{
                .visibility = .{ .fragment = true },
                .resource = .{
                    .texture = .{ .sample_type = .float, .view_dimension = .@"2d" },
                },
            },
            // Normal texture
            .{
                .visibility = .{ .fragment = true },
                .resource = .{
                    .texture = .{ .sample_type = .float, .view_dimension = .@"2d" },
                },
            },
            // Sampler
            .{
                .visibility = .{ .fragment = true },
                .resource = .{ .sampler = .{ .binding_type = .filtering } },
            },
            // Lighting
            .{
                .visibility = .{ .fragment = true },
                .resource = .{ .buffer = .{
                    .binding_type = .uniform,
                    .min_binding_size = @sizeOf(LightingUniform),
                } },
            },
        },
    };
    const bind_group_layout = try bind_group_thing.toApi(device, allocator);

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
        const normal_texture_binding: wgpu.BindGroup.Entry = .{
            .binding = 2,
            .texture_view = normal_texture_view,
        };
        const sampler_binding: wgpu.BindGroup.Entry = .{
            .binding = 3,
            .sampler = sampler,
        };
        const lighting_uniform_binding: wgpu.BindGroup.Entry = .{
            .binding = 4,
            .buffer = lighting_uniform_buffer,
            .size = @sizeOf(LightingUniform),
        };
        break :init try device.createBindGroup(.{
            .label = "My bind group",
            .layout = bind_group_layout,
            .entries = &.{
                uniform_binding,
                texture_binding,
                normal_texture_binding,
                sampler_binding,
                lighting_uniform_binding,
            },
        });
    };
    log.info("Bind group created", .{});
    return .{
        .queue = queue,
        .texture = .{ texture, texture_view },
        .normal_texture = normal_texture,
        .depth = .{ depth_texture, depth_texture_view },
        .bind_group = bind_group,
        .bind_group_layout = bind_group_layout,

        .shader = shader_module,
        .uniform_buffer = uniform_buffer,
        .lighting_uniform_buffer = lighting_uniform_buffer,
    };
}

pub const ShaderVisibility = struct {
    vertex: bool = false,
    fragment: bool = false,
    compute: bool = false,

    pub fn toApi(self: ShaderVisibility) wgpu.RenderPipeline.ShaderStage {
        return .{
            .vertex = self.vertex,
            .fragment = self.fragment,
            .compute = self.compute,
        };
    }
};

pub const BindGroup = struct {
    pub const Layout = struct {
        entries: []const Entry,
        label: []const u8 = "",

        pub const Entry = struct {
            binding: ?u32 = null,
            visibility: ShaderVisibility = .{},
            resource: Resource,
        };

        pub const Resource = union(enum) {
            buffer: wgpu.BindGroupLayout.BufferBindingLayout,
            texture: wgpu.BindGroupLayout.TextureBindingLayout,
            sampler: wgpu.BindGroupLayout.SamplerBindingLayout,
        };

        pub fn toApi(layout: Layout, device: wgpu.Device, allocator: std.mem.Allocator) !wgpu.BindGroupLayout {
            const buffer = try allocator.alloc(wgpu.BindGroupLayout.Entry, layout.entries.len);
            defer allocator.free(buffer);
            for (layout.entries, 0..) |e, i| {
                const binding: u32 = @intCast(e.binding orelse i);
                const wgpu_entry: wgpu.BindGroupLayout.Entry = switch (e.resource) {
                    .buffer => |b| .{
                        .binding = binding,
                        .visibility = e.visibility.toApi(),
                        .buffer = b,
                    },
                    .texture => |t| .{
                        .binding = binding,
                        .visibility = e.visibility.toApi(),
                        .texture = t,
                    },
                    .sampler => |s| .{
                        .binding = binding,
                        .visibility = e.visibility.toApi(),
                        .sampler = s,
                    },
                };
                buffer[i] = wgpu_entry;
            }
            return try device.createBindGroupLayout(.{ .entries = buffer, .label = layout.label });
        }
    };
};

fn initDepthTexture(surface_width: u32, surface_height: u32, device: wgpu.Device) !TextureAndView {
    const depth_texture = try device.createTexture(.{
        .usage = .{ .render_attachment = true },
        .dimension = .@"2d",
        .format = .depth24_plus,
        .size = .{
            .width = surface_width,
            .height = surface_height,
        },
    });
    const depth_texture_view = try depth_texture.createView(.{
        .aspect = .depth_only,
        .dimension = .@"2d",
        .format = .depth24_plus,
    });
    return .{ depth_texture, depth_texture_view };
}

fn resizeWindow(core: *Core, new_width: u32, new_height: u32) void {
    core.surface.configure(.{
        .device = core.device,
        .width = new_width,
        .height = new_height,
        .format = core.surface_format,
        .usage = .{ .render_attachment = true },
    });

    core.depth_texture.deinit();
    core.depth_texture_view.deinit();
    const new_depth = initDepthTexture(new_width, new_height, core.device) catch |err| {
        log.err("resize: failed to recreate depth texture: {s}", .{@errorName(err)});
        return;
    };
    core.depth_texture = new_depth.@"0";
    core.depth_texture_view = new_depth.@"1";
}

fn onWindowResizeCallback(window: *Window, width: c_int, height: c_int) callconv(.c) void {
    const self: *Core = window.getUserPointer(Core) orelse return;
    if (width <= 0 or height <= 0) return; // window minimized
    self.resizeWindow(@intCast(width), @intCast(height));
}

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

pub fn formatFromType(comptime T: type) wgpu.RenderPipeline.VertexFormat {
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

pub fn loadTextureFromFile(filename: []const u8, mip_level_count: u32, device: wgpu.Device, allocator: std.mem.Allocator) !TextureAndView {
    const channels = 4;
    const filename_sentinel = try allocator.dupeSentinel(u8, filename, 0);
    defer allocator.free(filename_sentinel);
    var loaded_image = try stbi.Image.loadFromFile(filename_sentinel, channels);
    defer loaded_image.deinit();

    const texture_desc: wgpu.Texture.Descriptor = .{
        .dimension = .@"2d",
        .format = .rgba8_unorm,
        .mip_level_count = mip_level_count,
        .sample_count = 1,
        .size = .{ .width = loaded_image.width, .height = loaded_image.height },
        .usage = .{ .texture_binding = true, .copy_dst = true },
    };
    const texture = try device.createTexture(texture_desc);

    // Create and upload texture data, one mip level at a time. Each mip level
    // is generated by downsampling the previous one, which is what
    // `createMipMap` expects (the source is exactly 2x the destination size).
    const image: Image = .{
        .pixels = @ptrCast(loaded_image.data),
        .width = loaded_image.width,
        .height = loaded_image.height,
    };
    var previous_image = image;
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

        const queue = try device.getQueue();

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

    const texture_view = try texture.createView(.{
        .aspect = .all,
        .dimension = .@"2d",
        .format = texture.getFormat(),
        .mip_level_count = texture_desc.mip_level_count,
    });

    return .{ texture, texture_view };
}

/// OBJ files are Y-up; our world is Z-up.
fn objToWorld(ptr: [*c]f32, i: usize) Vec3f {
    return .{ ptr[3 * i + 0], -ptr[3 * i + 2], ptr[3 * i + 1] };
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
            .position = objToWorld(scene.attributes.vertices.ptr, vi),
            .tangent = @splat(0),
            .bitangent = @splat(0),
            .normal = objToWorld(scene.attributes.normals.ptr, ni),
            .color = if (scene.attributes.colors.count > 0) .{
                scene.attributes.colors.ptr[3 * vi + 0],
                scene.attributes.colors.ptr[3 * vi + 1],
                scene.attributes.colors.ptr[3 * vi + 2],
            } else .{ 1, 1, 1 },
            .uv = .{
                scene.attributes.texcoords.ptr[2 * ti + 0],
                1 - scene.attributes.texcoords.ptr[2 * ti + 1],
            },
        };
    }

    // Per triangle, compute tangent/bitangent per corner (normal stays the
    // smooth OBJ normal).
    var t: usize = 0;
    while (t + 2 < shape.mesh.num_indices) : (t += 3) {
        const corners = vertices[t .. t + 3];
        inline for (0..3) |k| {
            const tbn = computeTBN(corners, vertices[t + k].normal);
            vertices[t + k].tangent = tbn[0];
            vertices[t + k].bitangent = tbn[1];
        }
    }

    return vertices;
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

const SurfaceTarget = struct {
    view: wgpu.TextureView,
    width: u32,
    height: u32,
};

fn getNextSurfaceTextureView(surface: wgpu.Surface) !?SurfaceTarget {
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
    const view = try wgpu.TextureView.init(
        surface_texture.texture,
        wgpu.TextureView.Descriptor{
            .label = "Surface texture view",
            .format = surface_texture.getFormat(),
            .dimension = .@"2d",
            .aspect = .all,
        },
    );
    return .{
        .view = view,
        .width = surface_texture.getWidth(),
        .height = surface_texture.getHeight(),
    };
}

fn computeTBN(corners: []const Vertex, expected_normal: Vec3f) [3]Vec3f {
    const p0 = corners[0].position;
    const p1 = corners[1].position;
    const p2 = corners[2].position;

    const e1 = p1 - p0;
    const e2 = p2 - p0;

    const duv1 = corners[1].uv - corners[0].uv;
    const duv2 = corners[2].uv - corners[0].uv;

    const det = duv1[0] * duv2[1] - duv2[0] * duv1[1];
    if (det == 0) return .{ .{ 1, 0, 0 }, .{ 0, 1, 0 }, expected_normal };

    var tangent = normalize(e1 * @as(Vec3f, @splat(duv2[1])) - e2 * @as(Vec3f, @splat(duv1[1])));
    var bitangent = normalize(e2 * @as(Vec3f, @splat(duv1[0])) - e1 * @as(Vec3f, @splat(duv2[0])));
    var normal = normalize(crossProduct(tangent, bitangent));

    // Match the vertex normal's orientation, then orthonormalize.
    if (dot(normal, expected_normal) < 0) {
        tangent = -tangent;
        bitangent = -bitangent;
        normal = -normal;
    }
    tangent = normalize(tangent - expected_normal * @as(Vec3f, @splat(dot(tangent, expected_normal))));
    bitangent = crossProduct(expected_normal, tangent);

    return .{ tangent, bitangent, expected_normal };
}

fn dot(a: Vec3f, b: Vec3f) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

fn normalize(v: Vec3f) Vec3f {
    const len = @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (len == 0) return @splat(0);
    return v / @as(Vec3f, @splat(len));
}

fn crossProduct(a: Vec3f, b: Vec3f) Vec3f {
    return .{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}

/// Called by wgpu whenever an error reaches the queue/device without being
/// captured by an error scope. Logging it here turns the terse "pipeline is
/// invalid" submit-time panic into the actual validation message.
fn onUncapturedError(err_type: wgpu.c.WGPUErrorType, message: []const u8) void {
    const name: []const u8 = switch (err_type) {
        wgpu.c.WGPUErrorType_Validation => "Validation",
        wgpu.c.WGPUErrorType_OutOfMemory => "OutOfMemory",
        wgpu.c.WGPUErrorType_Internal => "Internal",
        wgpu.c.WGPUErrorType_Unknown => "Unknown",
        else => "NoError/Other",
    };
    log.err("wgpu {s} error: {s}", .{ name, message });
}

fn color(c: Color) wgpu.Color {
    return .{ .r = c[0], .g = c[1], .b = c[2], .a = 1 };
}

fn vec4(v: Vec3f, w: f32) [4]f32 {
    return .{ v[0], v[1], v[2], w };
}
