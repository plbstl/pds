const std = @import("std");

pub fn build(b: *std.Build) void {
    const pds_mod = b.addModule("pds", .{
        .root_source_file = b.path("src/root.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });

    // zig build test
    const test_step = b.step("test", "Run unit tests");
    const pds_mod_tests = b.addTest(.{ .root_module = pds_mod });
    const run_pds_mod_tests = b.addRunArtifact(pds_mod_tests);
    test_step.dependOn(&run_pds_mod_tests.step);
}
