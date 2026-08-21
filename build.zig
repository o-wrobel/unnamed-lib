const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wgpu_dep = b.dependency("wgpu", .{});
    const wgpu = wgpu_dep.module("wgpu");

    const glfw_dep = b.dependency("zglfw", .{});
    const glfw = glfw_dep.module("root");
    const glfw_lib = glfw_dep.artifact("glfw");

    const tiny_obj_dep = b.dependency("obj", .{});
    const tiny_obj = tiny_obj_dep.module("tiny_obj");

    const app_mod = b.createModule(.{
        .root_source_file = b.path("src/App.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .module = wgpu, .name = "wgpu" },
            .{ .module = glfw, .name = "glfw" },
            .{ .module = tiny_obj, .name = "tiny_obj" },
        }
    });
    app_mod.linkLibrary(glfw_lib);

    // On NixOS, X11/Wayland are not in default linker paths.
    // Add them from the LIBRARY_PATH env var set in flake.nix.
    if (b.graph.environ_map.get("LIBRARY_PATH")) |lib_path| {
        var it = std.mem.splitScalar(u8, lib_path, ':');
        while (it.next()) |dir| {
            app_mod.addLibraryPath(.{ .cwd_relative = dir });
        }
    }

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .module = wgpu, .name = "wgpu" },
            .{ .module = glfw, .name = "glfw" },
            .{ .module = app_mod, .name = "App" }
        }
    });
    exe_mod.linkLibrary(glfw_lib);

    // On NixOS, X11/Wayland are not in default linker paths.
    // Add them from the LIBRARY_PATH env var set in flake.nix.
    if (b.graph.environ_map.get("LIBRARY_PATH")) |lib_path| {
        var it = std.mem.splitScalar(u8, lib_path, ':');
        while (it.next()) |dir| {
            exe_mod.addLibraryPath(.{ .cwd_relative = dir });
        }
    }
    const exe = b.addExecutable(.{
        .name = "wgpu",
        .root_module = exe_mod
    });



    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
