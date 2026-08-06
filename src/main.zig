const std = @import("std");

const App = @import("App");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const app = try App.init(gpa, io);
    defer app.deinit();

    try app.mainLoop();

}
