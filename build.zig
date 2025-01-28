const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ztoml_dep = b.dependency("ztoml", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zduel",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const docs = b.addSystemCommand(&.{
        "zig",
        "test",
        "-fno-emit-bin",
        "-femit-docs",
        "src/zduel.zig",
    });

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&docs.step);

    exe.root_module.addImport("ztoml", ztoml_dep.module("ztoml"));

    b.installArtifact(exe);
}
