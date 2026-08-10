const std = @import("std");

const App = @import("App");
const Model = App.Model;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const cwd = std.Io.Dir.cwd();

    const model_file = try cwd.openFile(io, "model.zon", .{});
    const file_len = model_file.length(io) catch unreachable;
    var file_reader = model_file.reader(io, &.{});
    const text = try file_reader.interface.allocRemaining(gpa, .limited64(file_len+1));
    const text_sentinel = try gpa.dupeSentinel(u8, text, 0);
    defer gpa.free(text);
    defer gpa.free(text_sentinel);

    const model: Model = try std.zon.parse.fromSliceAlloc(Model, gpa, text_sentinel, null, .{});
    defer gpa.free(model.vertices);
    defer gpa.free(model.indices);

    const app = try App.init(model, gpa, io);
    defer app.deinit();

    try app.mainLoop();

}
