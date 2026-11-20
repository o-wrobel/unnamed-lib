const std = @import("std");

const glfw = @import("glfw");
const Window = glfw.Window;

const Core = @import("Core.zig");
pub const SceneOptions = Core.SceneOptions;
pub const UiDraw = Core.UiDraw;
pub const Input = @import("Input.zig");
pub const math = @import("math.zig");

pub const Context = @This();

core: *Core,

input: Input,
should_close: bool = false,
time: f32 = 0,
delta_time: f32 = 0,

const log = std.log.scoped(.UnnamedLib);

pub fn init(options: Core.InitOptions, allocator: std.mem.Allocator, io: std.Io) !Context {
    const core = try Core.init(options, allocator, io);
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

pub fn tick(context: *Context, scene_options: SceneOptions, ui_draw: ?UiDraw) !void {
    context.should_close = context.core.window.shouldClose();
    context.delta_time = @floatCast(glfw.getTime() - context.time);
    context.time = @floatCast(glfw.getTime());
    try context.core.tick(scene_options, ui_draw);
    context.input.update(context.core.window);
}
