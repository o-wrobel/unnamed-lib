const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wgpu_dep = b.dependency("wgpu", .{});
    const wgpu = wgpu_dep.module("wgpu");

    const glfw_dep = b.dependency("zglfw", .{});
    const glfw = glfw_dep.module("root");
    const glfw_lib = glfw_dep.artifact("glfw");

    const tinyobj_dep = b.dependency("tinyobjloader", .{});
    const tinyobjloader = tinyobj_dep.module("tinyobjloader");

    const stbi_dep = b.dependency("zstbi", .{});
    const stbi = stbi_dep.module("root");

    const math = b.createModule(.{
        .root_source_file = b.path("src/math.zig"),
        .target = target,
        .optimize = optimize,
    });

    const types = b.addModule("types", .{
        .root_source_file = b.path("src/types.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .module = wgpu, .name = "wgpu" }},
    });

    const defaults = b.addModule("defaults", .{
        .root_source_file = b.path("src/default.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .module = math, .name = "math" },
            .{ .module = types, .name = "types" },
        },
    });

    const root = b.addModule("unnamedlib", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .module = math, .name = "math" },
            .{ .module = types, .name = "types" },
            .{ .module = defaults, .name = "defaults" },
            .{ .module = wgpu, .name = "wgpu" },
            .{ .module = glfw, .name = "glfw" },
            .{ .module = tinyobjloader, .name = "tinyobj" },
            .{ .module = stbi, .name = "stbi" },
        },
    });
    root.linkLibrary(glfw_lib);

    // On NixOS, X11/Wayland are not in default linker paths.
    // Add them from the LIBRARY_PATH env var set in flake.nix.
    if (b.graph.environ_map.get("LIBRARY_PATH")) |lib_path| {
        var it = std.mem.splitScalar(u8, lib_path, ':');
        while (it.next()) |dir| {
            root.addLibraryPath(.{ .cwd_relative = dir });
        }
    }
}
