const std = @import("std");

const glfw = @import("glfw");
const Window = glfw.Window;
const wgpu = @import("wgpu");
const obj = @import("tiny_obj");
const Scene = obj.Scene;

pub const Vec2f = @Vector(2, f32);
pub const Vec3f = @Vector(3, f32);
pub const Color = @Vector(3, f32);

pub const Mat4x4 = [16]f32;
pub const identity_matrix: Mat4x4 = .{
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1
};

const uniform_stride = 256;

pub const Index = u32;

pub const Vertex = struct {
    const pos_format: wgpu.RenderPipeline.VertexFormat = .float32x3;
    const norm_format: wgpu.RenderPipeline.VertexFormat = .float32x3;
    const col_format: wgpu.RenderPipeline.VertexFormat = .float32x3;
    position: Vec3f,
    normal: Vec3f,
    color: Color
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
const background_color: Color = .{0.1, 0.1, 0.1};

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
    const window: *Window = try .create(window_width, window_height, "Hello, GLFW!", null, null);

    // WGPU
    const instance = try wgpu.Instance.init(null);
    defer instance.deinit();

    const adapter = try instance.requestAdapterSync(.{});
    defer adapter.deinit();
    // printLimits(try adapter.getLimits());

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
            .width = window_width,
            .height = window_height,
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
        const normal_attribute: wgpu.RenderPipeline.VertexAttribute = .{
            .shader_location = 1,
            .format = Vertex.norm_format,
            .offset = 1 * @sizeOf(Vec3f),
        };
        const color_attribute: wgpu.RenderPipeline.VertexAttribute = .{
            .shader_location = 2,
            .format = Vertex.col_format,
            .offset = 2 * @sizeOf(@Vector(3, f32))
        };
        const vertex_buffer_layout: wgpu.RenderPipeline.VertexBufferLayout = .{
            .array_stride = @sizeOf(Vertex),
            .attributes = &.{ position_attribute, normal_attribute, color_attribute },
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
            .depth_stencil = .{
                .depth_compare = .less,
                .depth_write_enabled = true,
                .format = .depth24_plus,
                .stencil_read_mask = 0,
                .stencil_write_mask = 0
            },
        });
    };

    const vertex_buffer, const vertex_count: u32 = init: {
        const vertex_buffer = try device.createBuffer(.{
            .size = vertices.len * @sizeOf(Vertex),
            .usage = .{ .copy_dst = true, .vertex = true }
        });
        queue.writeBuffer(Vertex, vertex_buffer, 0, vertices);
        break :init .{ vertex_buffer, @intCast(vertices.len )};
    };

    const depth_texture = try device.createTexture(.{
        .usage = .{ .render_attachment = true },
        .dimension = .@"2d",
        .format = .depth24_plus,
        .size = .{ .width = window_width, .height = window_height, },
    });
    const depth_texture_view = try depth_texture.createView(.{
        .aspect = .depth_only,
        .dimension = .@"2d",
        .format = .depth24_plus,
    });

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
    self.uniform_buffer.deinit();
}

pub fn mainLoop(self: *const App) !void {
    log.info("Executing main loop", .{});
    while (true) {
        glfw.pollEvents();
        if (glfw.windowShouldClose(self.window)) break;
        const time: f32 = @floatCast(glfw.getTime());

        const scale_coef = 0.3;
        const translate_vec: Vec3f = .{0, 0, 0};
        const model_roll = time;
        const model_transform = init: {
            const scale = transpose(.{
                scale_coef, 0, 0, 0,
                0, scale_coef, 0, 0,
                0, 0, scale_coef, 0,
                0, 0, 0, 1
            });
            const translate = transpose(.{
                1, 0, 0, translate_vec[0],
                0, 1, 0, translate_vec[1],
                0, 0, 1, translate_vec[2],
                0, 0, 0, 1
            });

            const rotation = rotationMatrix(0, 0, model_roll);
            break :init batchMatrixMultiply(&.{
                scale,
                translate,
                rotation
            });
        };

        const focal_point: Vec3f = .{0, 0, -1};
        const view_pitch = std.math.degreesToRadians(115);
        const view_transform = init: {
            const translation: Mat4x4 = transpose(.{
                1, 0, 0, -focal_point[0],
                0, 1, 0, -focal_point[1],
                0, 0, 1, -focal_point[2],
                0, 0, 0, 1
            });

            const rotation: Mat4x4 = rotationMatrix(view_pitch, 0, 0);
            break :init batchMatrixMultiply(&.{
                rotation,
                translation,
            });

        };

        const ratio: f32 = 640.0/480.0;
        const field_of_view: f32 = std.math.degreesToRadians(60);
        const focal_length: f32 = 1.0/@tan(field_of_view/2.0);
        const near: f32 = 0.01; const far: f32 = 100;
        const projection = init: {
            const divider = 1.0 / (focal_length * (far - near));
            break :init transpose(.{
                1, 0, 0, 0,
                0, ratio, 0, 0,
                0, 0, far*divider, -far * near * divider,
                0, 0, 1.0 / focal_length, 0
            });
        };

        const uniform1: MyUniform = .{
            .time = time,
            .model_tranform = model_transform,
            .view_transform = view_transform,
            .projection_transform = projection
        };
        self.queue.writeBuffer(MyUniform, self.uniform_buffer, 0, &.{ uniform1 });
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
            }
        });

        render_pass.setPipeline(self.render_pipeline);

        render_pass.setVertexBuffer(0, self.vertex_buffer, 0, self.vertex_buffer.size);

        render_pass.setBindGroup(0, self.bind_group, &.{ 0 });
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

pub fn loadOBJ(filename: []const u8, allocator: std.mem.Allocator, io: std.Io) ![]Vertex {
    const model_file = try std.Io.Dir.cwd().openFile(io, filename, .{});
    const file_len = model_file.length(io) catch unreachable;
    var file_reader = model_file.reader(io, &.{});
    const text = try file_reader.interface.allocRemaining(allocator, .limited64(file_len+1));
    defer allocator.free(text);

    const scene = try obj.loadFromMemory(text, null);
    const shape = (scene.shapes orelse unreachable)[0];
    const vertices = try allocator.alloc(Vertex, @intCast(shape.mesh.num_indices));

    for (0..shape.mesh.num_indices) |i| {
        const index = shape.mesh.indices[i];
        const vi: usize = @intCast(index.vertex_index);
        const ni: usize = @intCast(index.normal_index);
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

fn printMatrix(mat: Mat4x4) void {
    std.debug.print("{}, {}, {}, {}\n", .{mat[0], mat[4], mat[8], mat[12]});
    std.debug.print("{}, {}, {}, {}\n", .{mat[1], mat[5], mat[9], mat[13]});
    std.debug.print("{}, {}, {}, {}\n", .{mat[2], mat[6], mat[10], mat[14]});
    std.debug.print("{}, {}, {}, {}\n", .{mat[3], mat[7], mat[11], mat[15]});
}

fn transpose(mat: Mat4x4) Mat4x4 {
    return .{
        mat[0], mat[4], mat[8], mat[12],
        mat[1], mat[5], mat[9], mat[13],
        mat[2], mat[6], mat[10], mat[14],
        mat[3], mat[7], mat[11], mat[15],
    };
}

/// -> m2 * m1
fn multiplyMatrices(m1: Mat4x4, m2: Mat4x4) Mat4x4 {
    var result: Mat4x4 = undefined;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        var j: usize = 0;
        while (j < 4) : (j += 1) {
            result[i + 4 * j] =
                m2[i + 0] * m1[0 + 4 * j] +
                m2[i + 4] * m1[1 + 4 * j] +
                m2[i + 8] * m1[2 + 4 * j] +
                m2[i + 12] * m1[3 + 4 * j];
        }
    }
    return result;
}

fn batchMatrixMultiply(mats: []const Mat4x4) Mat4x4 {
    return blk: {
        var temp: Mat4x4 = mats[0];
        for (mats[1..]) |m| temp = multiplyMatrices(temp, m);
        break :blk temp;
    };
}

fn rotationMatrix(pitch: f32, yaw: f32, roll: f32) Mat4x4 {
    const cr = @cos(roll);
    const sr = @sin(roll);
    const roll_tr = transpose(.{
        cr, sr, 0, 0,
        -sr, cr, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
    });

    const cy = @cos(yaw);
    const sy = @sin(yaw);
    const yaw_tr = transpose(.{
        cy, 0, -sy, 0,
        0, 1, 0, 0,
        sy, 0, cy, 0,
        0, 0, 0, 1
    });

    const cp = @cos(pitch);
    const sp = @sin(pitch);
    const pitch_tr = transpose(.{
        1, 0, 0, 0,
        0, cp, sp, 0,
        0, -sp, cp, 0,
        0, 0, 0, 1
    });
    return batchMatrixMultiply(&.{
        roll_tr,
        yaw_tr,
        pitch_tr
    });
}

fn color(c: Color) wgpu.Color {
    return .{
        .r = c[0],
        .g = c[1],
        .b = c[2],
        .a = 1
    };
}
