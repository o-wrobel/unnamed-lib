const std = @import("std");

const glfw = @import("glfw");
const Window = glfw.Window;
const obj = @import("tinyobj");
const Scene = obj.Scene;
const stbi = @import("stbi");
const wgpu = @import("wgpu");

const Core = @import("Core.zig");
pub const SceneOptions = Core.SceneOptions;
pub const MyUniform = Core.MyUniform;
pub const Input = @import("Input.zig");
pub const math = @import("math.zig");
pub const Rotation = math.Rotation;
const Mat4x4 = math.Mat4x4;
pub const Vec2f = math.Vec2f;
pub const Vec3f = math.Vec3f;
pub const modelTransform = math.modelTransform;
pub const viewTransform = math.viewTransform;
pub const projectionTransform = math.projectionTransform;

pub const Context = @This();
const log = std.log.scoped(.UnnamedLib);

core: *Core,
input: Input,
should_close: bool = false,
time: f32 = 0,
delta_time: f32 = 0,

pub fn init(
    model_filename: []const u8,
    texture_filename: []const u8,
    window_width: u32,
    window_height: u32,
    comptime input_options: Input.Options,
    allocator: std.mem.Allocator,
    io: std.Io,
) !Context {
    const core = try Core.init(
        model_filename,
        texture_filename,
        window_width,
        window_height,
        allocator,
        io,
    );
    const input = try Input.init(input_options, core.window);
    log.info("Input system created", .{});
    const context: Context = .{
        .core = core,
        .input = input,
    };
    return context;
}

pub fn deinit(context: *Context) void {
    log.info("Deinitializing", .{});
    context.core.deinit();
}

pub fn tick(context: *Context, scene_options: SceneOptions) !void {
    context.should_close = context.core.window.shouldClose();
    context.delta_time = @floatCast(glfw.getTime() - context.time);
    context.time = @floatCast(glfw.getTime());
    try context.core.tick(scene_options);
}
