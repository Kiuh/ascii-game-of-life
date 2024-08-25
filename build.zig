const std = @import("std");

const targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .aarch64, .os_tag = .linux },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .x86_64, .os_tag = .windows },
};

pub fn build(b: *std.Build) !void {
    const root_source_file = b.path("src/main.zig");
    const run_step = b.step("run", "Run the application");
    const test_step = b.step("test", "Run unit tests");

    for (targets) |t| {
        const exe = b.addExecutable(.{
            .name = "ascii-game-of-life",
            .root_source_file = root_source_file,
            .target = b.resolveTargetQuery(t),
            .optimize = .ReleaseSafe,
        });

        b.installArtifact(exe);

        const clap = b.dependency("clap", .{});
        exe.root_module.addImport("clap", clap.module("clap"));

        const target_output = b.addInstallArtifact(exe, .{
            .dest_dir = .{
                .override = .{
                    .custom = try t.zigTriple(b.allocator),
                },
            },
        });

        b.getInstallStep().dependOn(&target_output.step);

        // Add test command for current os type
        if (t.os_tag == .windows) {
            const unit_tests = b.addTest(.{
                .root_source_file = root_source_file,
                .target = b.resolveTargetQuery(t),
            });

            const run_unit_tests = b.addRunArtifact(unit_tests);
            test_step.dependOn(&run_unit_tests.step);
        }

        // Add run command for current os type
        if (t.os_tag == .windows) {
            const run_exe = b.addRunArtifact(exe);
            run_step.dependOn(&run_exe.step);
        }
    }
}
