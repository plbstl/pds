const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // public module
    const pds_mod = b.addModule("pds", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // zig build test
    const test_step = b.step("test", "Run unit tests");
    const pds_mod_tests = b.addTest(.{ .root_module = pds_mod });
    const run_pds_mod_tests = b.addRunArtifact(pds_mod_tests);
    test_step.dependOn(&run_pds_mod_tests.step);

    // zig build <example_name> [-Drun]
    const run_opt = b.option(bool, "run", "Auto run the example program after build") orelse false;
    for (examples) |example_name| {
        const desc = b.fmt("Build `{s}` example program. Use -Drun flag to auto run after build.", .{example_name});
        const build_step = b.step(example_name, desc);

        const path = b.fmt("examples/{s}.zig", .{example_name});
        const exe = b.addExecutable(.{
            .name = example_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "pds", .module = pds_mod },
                },
            }),
        });

        const exe_install = b.addInstallArtifact(exe, .{});
        build_step.dependOn(&exe_install.step);

        if (run_opt) {
            const run_cmd = b.addRunArtifact(exe);
            if (b.args) |args| run_cmd.addArgs(args);
            run_cmd.step.dependOn(b.getInstallStep());
            build_step.dependOn(&run_cmd.step);
        }
    }
}

const examples = [_][]const u8{};
