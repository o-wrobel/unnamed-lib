const std = @import("std");

const App = @import("App");

pub fn main(init: std.process.Init) !void {
    _ = init;
    const app = try App.init();
    defer app.deinit();

    try app.mainLoop();

}
