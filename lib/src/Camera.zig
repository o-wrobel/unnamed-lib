const std = @import("std");
const math = @import("math.zig");

pub const Camera = @This();

angles: [2]f32,
zoom: f32,

pub fn viewTransform(camera: *const Camera) math.Mat4x4 {
    const cx = @cos(camera.angles[0]);
    const sx = @sin(camera.angles[0]);
    const cy = @cos(camera.angles[1]);
    const sy = @sin(camera.angles[1]);
    const distance = @exp(-camera.zoom);

    const position = math.Vec3f{ cx * cy * distance, sx * cy * distance, sy * distance };
    return math.looKAt(position, math.Vec3f{ 0, 0, 0 }, math.up);
}
