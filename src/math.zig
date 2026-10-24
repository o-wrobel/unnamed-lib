const std = @import("std");

pub const Vec2f = @Vector(2, f32);
pub const Vec3f = @Vector(3, f32);

pub const Mat4x4 = [16]f32;
pub const identity_matrix: Mat4x4 = .{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 };
pub const ortho_projection: Mat4x4 = transpose(.{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1 });

/// In radians
const Rotation = struct { pitch: f32 = 0, yaw: f32 = 0, roll: f32 = 0 };

// Matrix functions

pub fn transpose(mat: Mat4x4) Mat4x4 {
    return .{
        mat[0], mat[4], mat[8],  mat[12],
        mat[1], mat[5], mat[9],  mat[13],
        mat[2], mat[6], mat[10], mat[14],
        mat[3], mat[7], mat[11], mat[15],
    };
}

/// -> m2 * m1
pub fn multiplyMatrices(m1: Mat4x4, m2: Mat4x4) Mat4x4 {
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

pub fn batchMatrixMultiply(mats: []const Mat4x4) Mat4x4 {
    return blk: {
        var temp: Mat4x4 = mats[0];
        for (mats[1..]) |m| temp = multiplyMatrices(temp, m);
        break :blk temp;
    };
}

pub fn rotationMatrix(pitch: f32, yaw: f32, roll: f32) Mat4x4 {
    const cr = @cos(roll);
    const sr = @sin(roll);
    const roll_tr = transpose(.{ cr, sr, 0, 0, -sr, cr, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 });

    const cy = @cos(yaw);
    const sy = @sin(yaw);
    const yaw_tr = transpose(.{ cy, 0, -sy, 0, 0, 1, 0, 0, sy, 0, cy, 0, 0, 0, 0, 1 });

    const cp = @cos(pitch);
    const sp = @sin(pitch);
    const pitch_tr = transpose(.{ 1, 0, 0, 0, 0, cp, sp, 0, 0, -sp, cp, 0, 0, 0, 0, 1 });
    return batchMatrixMultiply(&.{ roll_tr, yaw_tr, pitch_tr });
}

pub fn printMatrix(mat: Mat4x4) void {
    std.debug.print("{}, {}, {}, {}\n", .{ mat[0], mat[4], mat[8], mat[12] });
    std.debug.print("{}, {}, {}, {}\n", .{ mat[1], mat[5], mat[9], mat[13] });
    std.debug.print("{}, {}, {}, {}\n", .{ mat[2], mat[6], mat[10], mat[14] });
    std.debug.print("{}, {}, {}, {}\n", .{ mat[3], mat[7], mat[11], mat[15] });
}

// Transform functions

pub fn modelTransform(scale: f32, translation: Vec3f, rotation: Rotation) Mat4x4 {
    const scale_transform = transpose(.{ scale, 0, 0, 0, 0, scale, 0, 0, 0, 0, scale, 0, 0, 0, 0, 1 });
    const translation_transform = transpose(.{ 1, 0, 0, translation[0], 0, 1, 0, translation[1], 0, 0, 1, translation[2], 0, 0, 0, 1 });

    const rotation_transform = rotationMatrix(rotation.pitch, rotation.yaw, rotation.roll);
    return batchMatrixMultiply(&.{ scale_transform, translation_transform, rotation_transform });
}

pub fn viewTransform(focal_point: Vec3f, rotation: Rotation) Mat4x4 {
    const translation_transform: Mat4x4 = transpose(.{ 1, 0, 0, -focal_point[0], 0, 1, 0, -focal_point[1], 0, 0, 1, -focal_point[2], 0, 0, 0, 1 });

    const rotation_transform = rotationMatrix(rotation.pitch, rotation.yaw, rotation.roll);

    return batchMatrixMultiply(&.{
        rotation_transform,
        translation_transform,
    });
}

pub fn projectionTransform(view_ratio: f32, field_of_view: f32) Mat4x4 {
    const focal_length: f32 = 1.0 / @tan(field_of_view / 2.0);
    const near: f32 = 0.01;
    const far: f32 = 100;
    const divider = 1.0 / (focal_length * (far - near));
    return transpose(.{ 1, 0, 0, 0, 0, view_ratio, 0, 0, 0, 0, far * divider, -far * near * divider, 0, 0, 1.0 / focal_length, 0 });
}
