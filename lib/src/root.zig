const std = @import("std");

const glfw = @import("glfw");
const Window = glfw.Window;

const Core = @import("Core.zig");
pub const SceneOptions = Core.SceneOptions;
pub const Input = @import("Input.zig");
pub const math = @import("math.zig");

pub const Context = @This();

core: *Core,

input: Input,
should_close: bool = false,
time: f32 = 0,
delta_time: f32 = 0,

const log = std.log.scoped(.UnnamedLib);

pub fn init(
    model_filename: []const u8,
    texture_filename: []const u8,
    window_width: u32,
    window_height: u32,
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
    const input = try Input.init(core.window);
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
    context.input.update(context.core.window);
}
