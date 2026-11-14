const std = @import("std");

const ul = @import("engine");
const Model = ul.Model;
const Vertex = ul.Vertex;

fn callbackFunction() void {
    std.debug.print("Pressed space!\n", .{});
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    var args = init.minimal.args.iterate();
    _ = args.next();
    const model_filename = if (args.next()) |f| f else "cube.obj";
    const texture_filename = if (args.next()) |f| f else "texture.jpg";

    const press_callbacks = comptime ul.Input.CallbackMap.init(.{
        .space = &callbackFunction,
    });
    const input_options: ul.Input.Options = .{ .press_callbacks = press_callbacks };

    const window_width = 640;
    const window_height = 480;
    const context = try ul.init(
        model_filename,
        texture_filename,
        window_width,
        window_height,
        input_options,
        gpa,
        io,
    );
    defer context.deinit();
    const input = context.input;

    const camera_rotate_speed = 4;
    var model_pitch: f32 = 0;
    var model_roll: f32 = 0;
    while (!context.should_close) {
        const dt = context.delta_time;
        if (input.held(.up)) model_pitch += camera_rotate_speed * dt;
        if (input.held(.down)) model_pitch -= camera_rotate_speed * dt;

        if (input.held(.left)) model_roll -= camera_rotate_speed * dt;
        if (input.held(.right)) model_roll += camera_rotate_speed * dt;
        const model_transform = ul.modelTransform(
            0.3,
            .{ 0, 0, 0 },
            .{ .roll = model_roll, .pitch = model_pitch },
        );
        const view_transform = ul.viewTransform(
            .{ 0, 0, -1.2 },
            .{ .pitch = std.math.degreesToRadians(115) },
        );
        const projection_transform = ul.projectionTransform(
            640.0 / 480.0,
            std.math.degreesToRadians(60),
        );
        const uniform: ul.MyUniform = .{
            .time = context.time,
            .model_tranform = model_transform,
            .view_transform = view_transform,
            .projection_transform = projection_transform,
        };
        try context.tick(uniform);
    }
}
