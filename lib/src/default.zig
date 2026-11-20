const std = @import("std");
const Core = @import("Core.zig");
const math = @import("math.zig");
const Vec3f = math.Vec3f;
const Vec2f = math.Vec2f;
const Color = Vec3f;
const Mat4x4 = math.Mat4x4;
const identity_matrix = math.identity_matrix;

// This module exists to contain default types and values
// that could be also defined by the user, namely uniforms
// and a shader

pub const shader = @embedFile("default.wgsl");

pub const Uniform = extern struct {
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
    hardness: f32,
    diffuse_strength: f32,
    specular_strength: f32,
};

pub const Vertex = struct {
    position: Vec3f,

    tangent: Vec3f,
    bitangent: Vec3f,
    normal: Vec3f,

    color: Color,
    uv: Vec2f,
    pub const buffer_layout = Core.bufferLayout(@This());
};
