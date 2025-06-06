const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const websocket_dep = b.dependency("websocket", .{});
    const wardrobe_dep = b.dependency("wardrobe", .{});
    const datetime_dep = b.dependency("datetime", .{});

    const mod = b.addModule("zeppelin", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    mod.addImport("websocket", websocket_dep.module("websocket"));
    mod.addImport("wardrobe", wardrobe_dep.module("wardrobe"));
    mod.addImport("datetime", datetime_dep.module("datetime"));

    const example_mod = b.addModule("zeppelin-example", .{
        .root_source_file = b.path("src/example.zig"),
        .target = target,
        .optimize = optimize,
    });

    example_mod.addImport("zeppelin", mod);

    const example_exe = b.addExecutable(.{
        .name = "zeppelin-example",
        .root_module = example_mod,
    });

    if (optimize == .ReleaseFast or optimize == .ReleaseSmall) {
        example_exe.linkLibC();
    }

    b.installArtifact(example_exe);
}
