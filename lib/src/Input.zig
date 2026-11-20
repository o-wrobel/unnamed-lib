const std = @import("std");

const glfw = @import("glfw");
const Window = glfw.Window;
pub const Key = glfw.Key;
pub const MouseButton = glfw.MouseButton;

const math = @import("math");
const Vec2f = math.Vec2f;

pub const Input = @This();

keyboard: Keyboard = .{},
mouse: Mouse = .{},

pub fn init(window: *Window) !Input {
    // Sticky mode keeps a press visible to glfw.getKey even if the key was
    // released before we polled, so taps shorter than one frame aren't lost.
    try glfw.setInputMode(window, .sticky_keys, true);
    try glfw.setInputMode(window, .sticky_mouse_buttons, true);
    return .{};
}

/// Call once per frame, after `glfw.pollEvents()`. Moves this frame's state
/// into last frame's slot, then samples the window for the new state.
pub fn update(input: *Input, window: *Window) void {
    const keyboard = &input.keyboard;
    keyboard.previous_keys_down = keyboard.keys_down;
    for (Keyboard.polled_keys) |key| {
        const action = window.getKey(key);
        keyboard.keys_down.set(key, action == .press);
    }

    const mouse = &input.mouse;
    mouse.previous_buttons_down = mouse.buttons_down;
    for (std.enums.values(MouseButton)) |button| {
        const action = window.getMouseButton(button);
        mouse.buttons_down.set(button, action == .press);
    }

    const cursor = window.getCursorPos();
    const new_pos: Vec2f = .{ @floatCast(cursor[0]), @floatCast(cursor[1]) };
    mouse.delta = new_pos - mouse.position;
    mouse.position = new_pos;
}

pub const Keyboard = struct {
    keys_down: std.EnumArray(Key, bool) = .initFill(false),
    previous_keys_down: std.EnumArray(Key, bool) = .initFill(false),

    /// Every key GLFW can report. `Key.unknown` (-1) can't be polled, so it's skipped.
    const polled_keys = blk: {
        var keys: []const Key = &.{};
        for (@typeInfo(Key).@"enum".field_names) |name| {
            const key = @field(Key, name);
            if (@backingInt(key) >= 0) keys = keys ++ &[_]Key{key};
        }
        break :blk keys;
    };

    pub fn held(keyboard: *const Keyboard, key: Key) bool {
        return keyboard.keys_down.get(key);
    }

    pub fn pressed(keyboard: *const Keyboard, key: Key) bool {
        return keyboard.keys_down.get(key) and !keyboard.previous_keys_down.get(key);
    }

    pub fn released(keyboard: *const Keyboard, key: Key) bool {
        return !keyboard.keys_down.get(key) and keyboard.previous_keys_down.get(key);
    }
};

pub const Mouse = struct {
    buttons_down: std.EnumArray(MouseButton, bool) = .initFill(false),
    previous_buttons_down: std.EnumArray(MouseButton, bool) = .initFill(false),

    position: Vec2f = undefined,
    delta: Vec2f = undefined,

    pub fn buttonHeld(mouse: *const Mouse, button: MouseButton) bool {
        return mouse.buttons_down.get(button);
    }

    pub fn buttonPressed(mouse: *const Mouse, button: MouseButton) bool {
        return mouse.buttons_down.get(button) and !mouse.previous_buttons_down.get(button);
    }

    pub fn buttonReleased(mouse: *const Mouse, button: MouseButton) bool {
        return !mouse.buttons_down.get(button) and mouse.previous_buttons_down.get(button);
    }
};
