const std = @import("std");

const engine = @import("engine");
const Model = engine.Model;
const Vertex = engine.Vertex;

fn callbackFunction() void {
    std.debug.print("Pressed space!\n", .{});
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const press_callbacks = comptime engine.Input.CallbackMap.init(.{
        .space = &callbackFunction,
    });
    const input_options: engine.Input.Options = .{ .press_callbacks = press_callbacks };

    var device = try engine.init("fourareen/fourareen.obj", "fourareen/fourareen.jpg", input_options, gpa, io);
    defer device.deinit();
    const input = device.input;

    const camera_rotate_speed = 4;
    var model_pitch: f32 = 0;
    var model_roll: f32 = 0;
    while (!device.should_close) {
        const dt = device.delta_time;
        if (input.held(.up)) model_pitch += camera_rotate_speed * dt;
        if (input.held(.down)) model_pitch -= camera_rotate_speed * dt;

        if (input.held(.left)) model_roll -= camera_rotate_speed * dt;
        if (input.held(.right)) model_roll += camera_rotate_speed * dt;
        const model_transform = engine.modelTransform(
            0.3,
            .{ 0, 0, 0 },
            .{ .roll = model_roll, .pitch = model_pitch },
        );
        const view_transform = engine.viewTransform(
            .{ 0, 0, -1.2 },
            .{ .pitch = std.math.degreesToRadians(115) },
        );
        const projection_transform = engine.projectionTransform(
            640.0 / 480.0,
            std.math.degreesToRadians(60),
        );
        const uniform: engine.MyUniform = .{
            .time = device.time,
            .model_tranform = model_transform,
            .view_transform = view_transform,
            .projection_transform = projection_transform,
        };
        try device.tick(uniform);
    }
}
