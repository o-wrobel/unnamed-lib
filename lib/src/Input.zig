const std = @import("std");

const glfw = @import("glfw");
pub const Key = glfw.Key;
const Window = glfw.Window;

pub const Input = @This();

pub const Callback = *const fn () void;
pub const CallbackMap = std.EnumMap(Key, Callback);

window: *Window,
press_callbacks: CallbackMap,
release_callbacks: CallbackMap,

const log = std.log.scoped(.Input);

pub const Options = struct {
    press_callbacks: CallbackMap = .empty,
    release_callbacks: CallbackMap = .empty,
};

pub fn init(comptime options: Options, window: *Window) !Input {
    const gen = struct {
        fn key_callback(
            _: *Window,
            key: Key,
            _: c_int,
            action: glfw.Action,
            _: glfw.Mods,
        ) callconv(.c) void {
            switch (action) {
                .press => if (options.press_callbacks.get(key)) |cb| cb(),
                .release => if (options.release_callbacks.get(key)) |cb| cb(),
                .repeat => {},
            }
        }
    };
    _ = glfw.setKeyCallback(window, gen.key_callback);
    return .{
        .window = window,
        .press_callbacks = options.press_callbacks,
        .release_callbacks = options.release_callbacks,
    };
}

/// Returns whether the given key is held
/// Individual key presses can be set to have callbacks, when initializing an Input
pub fn held(input: Input, key: Key) bool {
    const action = glfw.getKey(input.window, key);
    return action == .press;
}
