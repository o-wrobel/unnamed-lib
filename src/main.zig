const std = @import("std");

const ul = @import("engine");
const ul_defaults = @import("defaults");
const imgui = @import("imgui");

var directions: [2]ul.math.Vec3f = .{
    .{ 1.0, -0.9, 0.1 },
    .{ 0.2, 0.4, 0.3 },
};
var colors: [2]ul.math.Vec3f = .{
    .{ 1, 0.9, 0.8 },
    .{ 1, 0.4, 0.1 },
};
var hardness: f32 = 2;
var diffuse_strength: f32 = 1;
var specular_strength: f32 = 0.5;

/// Draws the UI inside the render pass. `context` is a *Control, and
/// `width`/`height` are the render target's actual pixel size.
fn drawUi(context: ?*anyopaque, raw_pass: *anyopaque, width: u32, height: u32) void {
    _ = context;
    // Start the ImGui frame with the target size we are actually rendering
    // into. Doing this here (after the surface texture is acquired) avoids
    // stale display sizes on the frame where the window is resized.
    imgui.backend.newFrame(width, height);

    if (imgui.begin("Cube", .{})) {
        const framerate = imgui.io.getFramerate();
        imgui.text("Framerate: {}", .{@ceil(framerate)});
        _ = imgui.colorEdit3("Color #1", .{ .col = @ptrCast(&colors[0]) });
        _ = imgui.dragFloat3("Direction #1", .{ .v = @ptrCast(&directions[0]) });
        _ = imgui.colorEdit3("Color #2", .{ .col = @ptrCast(&colors[1]) });
        _ = imgui.dragFloat3("Direction #2", .{ .v = @ptrCast(&directions[1]) });
        _ = imgui.dragFloat("Hardness", .{
            .v = &hardness,
            .min = 0,
            .speed = 0.1,
        });
        _ = imgui.dragFloat("Diffuse strength", .{
            .v = &diffuse_strength,
            .min = 0,
            .speed = 0.1,
        });
        _ = imgui.dragFloat("Specular strength", .{
            .v = &specular_strength,
            .min = 0,
            .speed = 0.1,
        });
    }
    imgui.end();
    imgui.backend.draw(raw_pass);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    var args = init.minimal.args.iterate();
    _ = args.next();
    const model_filename = if (args.next()) |f| f else "cylinder.obj";
    const texture_filename = if (args.next()) |f| f else "texture.jpg";

    const window_width = 640;
    const window_height = 480;

    var ctx = try ul.init(.{
        .model_filename = model_filename,
        .texture_filename = texture_filename,
        .window_width = window_width,
        .window_height = window_height,
    }, gpa, io);

    defer ctx.deinit();
    const keyboard = &ctx.input.keyboard;
    const mouse = &ctx.input.mouse;

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

    var camera_pitch: f32 = std.math.degreesToRadians(0);
    var camera_roll: f32 = std.math.degreesToRadians(0);
    var camera_zoom: f32 = -1.2;

    while (!ctx.should_close) {
        if (keyboard.pressed(.escape)) break;

        const dt = ctx.delta_time;
        if (!imgui.io.getWantCaptureMouse()) {
            if (mouse.buttonHeld(.left)) {
                camera_roll += 0.5 * mouse.delta[0] * dt;
                camera_pitch += 0.5 * mouse.delta[1] * dt;
            }
        }
        if (keyboard.held(.up)) camera_zoom += 4 * dt;
        if (keyboard.held(.down)) camera_zoom -= 4 * dt;

        const scene_options: ul.SceneOptions = .{
            .model_transform = .{ .scale = 0.3 },
            .camera = .{
                .angles = .{ camera_roll, camera_pitch },
                .zoom = camera_zoom,
            },
            .projection_transform = .{ .vertical_field_of_view = std.math.degreesToRadians(60) },
            .lighting = .{
                .directions = directions,
                .colors = colors,
                .hardness = hardness,
                .diffuse_strength = diffuse_strength,
                .specular_strength = specular_strength,
            },
        };
        try ctx.tick(scene_options, .{ .context = null, .draw = &drawUi });
    }
}
