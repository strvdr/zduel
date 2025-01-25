const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zduel",

        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Install the executable
    b.installArtifact(exe);

    const docs = b.addSystemCommand(&[_][]const u8{
        "zig", "test", "-femit-docs", "src/main.zig",
    });

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&docs.step);

    // Install the executable
    b.installArtifact(exe);
}
