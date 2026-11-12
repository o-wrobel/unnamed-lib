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

    var device = try engine.init("models/cube.obj", input_options, gpa, io);
    defer device.deinit();
    const input = device.input;

    var temp: f32 = 0;
    while (!device.should_close) {
        if (input.held(.up)) temp += 0.01;
        if (input.held(.down)) temp -= 0.01;
        const model_transform = engine.modelTransform(
            0.3,
            .{ 0, 0, 0 },
            .{ .roll = device.delta_time, .pitch = temp },
        );
        const view_transform = engine.viewTransform(
            .{ 0, 0, -1 },
            .{ .pitch = std.math.degreesToRadians(115) },
        );
        const projection_transform = engine.projectionTransform(
            640.0 / 480.0,
            std.math.degreesToRadians(60),
        );
        const uniform: engine.MyUniform = .{
            .time = device.delta_time,
            .model_tranform = model_transform,
            .view_transform = view_transform,
            .projection_transform = projection_transform,
        };
        try device.tick(uniform);
    }
}
