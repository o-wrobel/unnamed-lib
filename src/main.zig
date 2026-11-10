const std = @import("std");

const engine = @import("engine");
const Model = engine.Model;
const Vertex = engine.Vertex;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var device = try engine.init("models/cube.obj", gpa, io);
    defer device.deinit();

    while (!device.should_close) {
        const model_transform = engine.modelTransform(
            0.3,
            .{ 0, 0, 0 },
            .{ .roll = device.delta_time },
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
