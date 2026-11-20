const std = @import("std");
const math = @import("math");
const Vec3f = math.Vec3f;

pub const Camera = @This();

angles: [2]f32,
zoom: f32,

pub fn viewTransform(camera: *const Camera) math.Mat4x4 {
    const pos = camera.position();
    return math.looKAt(pos, math.Vec3f{ 0, 0, 0 }, math.up);
}

pub fn position(camera: *const Camera) Vec3f {
    const cx = @cos(camera.angles[0]);
    const sx = @sin(camera.angles[0]);
    const cy = @cos(camera.angles[1]);
    const sy = @sin(camera.angles[1]);
    const distance = @exp(-camera.zoom);

    return .{ cx * cy * distance, sx * cy * distance, sy * distance };
}
