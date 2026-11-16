const std = @import("std");

const glfw = @import("glfw");
const Window = glfw.Window;
pub const Key = glfw.Key;
pub const MouseButton = glfw.MouseButton;

const math = @import("math.zig");
const Vec2f = math.Vec2f;

pub const Input = @This();

/// Large enough for every GLFW key code (the highest is `menu = 348`).
const key_count = 512;
const mouse_button_count = @typeInfo(MouseButton).@"enum".field_names.len;

/// Every key GLFW can report. `Key.unknown` (-1) can't be polled, so it's skipped.
const polled_keys = blk: {
    var keys: []const Key = &.{};
    for (@typeInfo(Key).@"enum".field_names) |name| {
        const key = @field(Key, name);
        if (@backingInt(key) >= 0) keys = keys ++ &[_]Key{key};
    }
    break :blk keys;
};

window: *Window,

keys_down: std.EnumArray(Key, bool) = undefined,
keys_down_last_frame: std.EnumArray(Key, bool) = undefined,

mouse_down: std.EnumArray(MouseButton, bool) = undefined,
mouse_down_last_frame: std.EnumArray(MouseButton, bool) = undefined,

mouse_pos: Vec2f = @splat(0),
mouse_delta: Vec2f = @splat(0),

pub fn init(window: *Window) !Input {
    // Sticky mode keeps a press visible to glfw.getKey even if the key was
    // released before we polled, so taps shorter than one frame aren't lost.
    try glfw.setInputMode(window, .sticky_keys, true);
    try glfw.setInputMode(window, .sticky_mouse_buttons, true);
    return .{ .window = window };
}

/// Call once per frame, after `glfw.pollEvents()`. Moves this frame's state
/// into last frame's slot, then samples the window for the new state.
pub fn update(input: *Input) void {
    input.keys_down_last_frame = input.keys_down;
    for (polled_keys) |key| {
        const action = input.window.getKey(key);
        input.keys_down.set(key, action == .press);
    }

    input.mouse_down_last_frame = input.mouse_down;
    for (std.enums.values(MouseButton)) |button| {
        const action = input.window.getMouseButton(button);
        input.mouse_down.set(button, action == .press);
    }

    const cursor = input.window.getCursorPos();
    const new_pos: Vec2f = .{ @floatCast(cursor[0]), @floatCast(cursor[1]) };
    input.mouse_delta = new_pos - input.mouse_pos;
    input.mouse_pos = new_pos;
}

pub fn pressed(input: *const Input, key: Key) bool {
    return input.keys_down.get(key) and !input.keys_down_last_frame.get(key);
}

pub fn held(input: *const Input, key: Key) bool {
    return input.keys_down.get(key);
}

pub fn released(input: *const Input, key: Key) bool {
    const i: usize = @intCast(@backingInt(key));
    return !input.keys_down[i] and input.keys_down_last_frame[i];
}

pub fn mousePressed(input: *const Input, button: MouseButton) bool {
    const i: usize = @intCast(@backingInt(button));
    return input.mouse_down[i] and !input.mouse_down_last_frame[i];
}

pub fn mouseHeld(input: *const Input, button: MouseButton) bool {
    return input.mouse_down[@intCast(@backingInt(button))];
}

pub fn mouseReleased(input: *const Input, button: MouseButton) bool {
    const i: usize = @intCast(@backingInt(button));
    return !input.mouse_down[i] and input.mouse_down_last_frame[i];
}

pub fn mousePos(input: *const Input) Vec2f {
    return input.mouse_pos;
}

pub fn mouseDelta(input: *const Input) Vec2f {
    return input.mouse_delta;
}
