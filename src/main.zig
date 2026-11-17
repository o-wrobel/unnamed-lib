const std = @import("std");

const ul = @import("engine");
const imgui = @import("imgui");

/// Draws the UI inside the render pass. `context` is a *f32 (the model roll).
fn drawUi(context: ?*anyopaque, raw_pass: *anyopaque) void {
    _ = context; // autofix

    // const roll: *f32 = @ptrCast(@alignCast(context.?));
    if (imgui.begin("Cube", .{})) {
        const framerate = imgui.io.getFramerate();
        imgui.text("Framerate: {}", .{@ceil(framerate)});
    }
    imgui.end();
    imgui.backend.draw(raw_pass);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    var args = init.minimal.args.iterate();
    _ = args.next();
    const model_filename = if (args.next()) |f| f else "cube.obj";
    const texture_filename = if (args.next()) |f| f else "texture.jpg";

    const window_width = 640;
    const window_height = 480;
    var ctx = try ul.init(
        model_filename,
        texture_filename,
        window_width,
        window_height,
        gpa,
        io,
    );
    defer ctx.deinit();
    const keyboard = &ctx.input.keyboard;
    const mouse = &ctx.input.mouse;

    var camera_pitch: f32 = std.math.degreesToRadians(115);
    var camera_roll: f32 = 0;

    // Imgui
    imgui.init(gpa);
    const swapchain_format: u32 = @intCast(@backingInt(ctx.core.surface_format));
    const depth_format: u32 = @intCast(@backingInt(ctx.core.depth_texture.getFormat()));
    imgui.backend.init(
        ctx.core.window,
        ctx.core.device.device,
        swapchain_format,
        depth_format,
    );
    defer imgui.deinit();
    defer imgui.backend.deinit();
    _ = imgui.io.addFontDefault(null);

    while (!ctx.should_close) {
        if (keyboard.pressed(.escape)) break;

        const dt = ctx.delta_time;
        if (!imgui.io.getWantCaptureMouse()) {
            if (mouse.buttonHeld(.left)) {
                camera_roll += 0.5 * mouse.delta[0] * dt;
                camera_pitch += 0.5 * mouse.delta[1] * dt;
            }
        }

        const scene_options: ul.SceneOptions = .{
            .model_transform = .{ .scale = 0.3 },
            .view_transform = .{
                .focal_point = .{ 0, 0, -1.2 },
                .rotation = .{
                    .pitch = camera_pitch,
                    .roll = camera_roll,
                },
            },
            .projection_transform = .{ .vertical_field_of_view = std.math.degreesToRadians(60) },
        };
        const fb = ctx.core.window.getFramebufferSize();
        imgui.backend.newFrame(@intCast(fb[0]), @intCast(fb[1]));
        try ctx.tick(scene_options, .{ .context = &camera_roll, .draw = &drawUi });
    }
}
