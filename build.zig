const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_dep = b.dependency("lib", .{});
    const root = lib_dep.module("unnamedlib");

    const zgui = b.dependency("zgui", .{ .backend = .glfw_wgpu });
    const imgui = zgui.module("root");

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .module = root, .name = "engine" },
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
