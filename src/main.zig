const std = @import("std");

const App = @import("App");
const Model = App.Model;
const Vertex = App.Vertex;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const app = try App.init("mammoth.obj", gpa, io);
    defer app.deinit();

    try app.mainLoop();
}
