const std = @import("std");

const ul = @import("engine");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    var args = init.minimal.args.iterate();
    _ = args.next();
    const model_filename = if (args.next()) |f| f else "cube.obj";
    const texture_filename = if (args.next()) |f| f else "texture.jpg";

    const window_width = 640;
    const window_height = 480;
    var context = try ul.init(
        model_filename,
        texture_filename,
        window_width,
        window_height,
        gpa,
        io,
    );
    defer context.deinit();

    const input = &context.input;

    const camera_rotate_speed = 4;
    var model_pitch: f32 = 0;
    var model_roll: f32 = 0;
    while (!context.should_close) {
        if (input.pressed(.escape)) break;

        const dt = context.delta_time;
        if (input.held(.up)) model_pitch += camera_rotate_speed * dt;
        if (input.held(.down)) model_pitch -= camera_rotate_speed * dt;

        if (input.held(.left)) model_roll -= camera_rotate_speed * dt;
        if (input.held(.right)) model_roll += camera_rotate_speed * dt;

        const scene_options: ul.SceneOptions = .{
            .model_transform = .{
                .scale = 0.3,
                .rotation_along_origin = .{
                    .roll = model_roll,
                    .pitch = model_pitch,
                },
            },
            .view_transform = .{
                .focal_point = .{ 0, 0, -1.2 },
                .rotation = .{ .pitch = std.math.degreesToRadians(115) },
            },
            .projection_transform = .{ .vertical_field_of_view = std.math.degreesToRadians(60) },
        };
        try context.tick(scene_options);
    }
}
