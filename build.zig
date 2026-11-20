const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const unnamedlib_dep = b.dependency("lib", .{});
    const unnamedlib = unnamedlib_dep.module("unnamedlib");
    const ul_defaults = unnamedlib_dep.module("defaults");

    const zgui = b.dependency("zgui", .{ .backend = .glfw_wgpu });
    const imgui = zgui.module("root");

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .module = unnamedlib, .name = "engine" },
            .{ .module = ul_defaults, .name = "defaults" },
            .{ .module = imgui, .name = "imgui" },
        },
    });
    const exe = b.addExecutable(.{ .name = "wgpu", .root_module = exe_mod });
    exe.root_module.linkLibrary(zgui.artifact("imgui"));

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
}
