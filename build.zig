const std = @import("std");

pub fn build(b: *std.Build) void {
    const logging = b.option(bool, "logging", "Whether the library should emit information through logging") orelse false;

    const build_options = b.addOptions();
    build_options.addOption(bool, "logging", logging);

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

    mod.addOptions("build_options", build_options);

    mod.addImport("websocket", websocket_dep.module("websocket"));
    mod.addImport("wardrobe", wardrobe_dep.module("wardrobe"));
    mod.addImport("datetime", datetime_dep.module("datetime"));

    const example_mod = b.addModule("zeppelin-example", .{
        .root_source_file = b.path("src/example.zig"),
        .target = target,
        .optimize = optimize,
    });

    example_mod.addImport("zeppelin", mod);
    example_mod.addImport("wardrobe", wardrobe_dep.module("wardrobe"));

    const example_exe = b.addExecutable(.{
        .name = "zeppelin-example",
        .root_module = example_mod,
    });

    if (target.result.os.tag == .windows) {
        example_exe.linkSystemLibrary("ws2_32");
        example_exe.linkSystemLibrary("crypt32");
    }

    if (optimize == .ReleaseFast or optimize == .ReleaseSmall) {
        example_exe.linkLibC();
    }

    b.installArtifact(example_exe);
}
