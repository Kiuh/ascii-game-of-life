const std = @import("std");

pub fn build(b: *std.Build) !void {
    const root_source_file = b.path("src/main.zig");
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ascii-game-of-life",
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    // Clap dependency
    const clap = b.dependency("clap", .{});
    exe.root_module.addImport("clap", clap.module("clap"));

    // Add test command for current os type
    const unit_tests = b.addTest(.{
        .root_source_file = root_source_file,
        .target = target,
    });

    // Add test command
    const test_step = b.step("test", "Run unit tests");
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);

    // Add run command
    const run_step = b.step("run", "Run the application");
    const run_exe = b.addRunArtifact(exe);
    run_step.dependOn(&run_exe.step);
}
