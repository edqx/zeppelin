const std = @import("std");

const Example = enum {
    slash_commands,
    mentions,
    buttons,
};

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
        .imports = &.{
            .{ .name = "websocket", .module = websocket_dep.module("websocket") },
            .{ .name = "wardrobe", .module = wardrobe_dep.module("wardrobe") },
            .{ .name = "datetime", .module = datetime_dep.module("datetime") },
        },
    });

    mod.addOptions("build_options", build_options);

    if (target.result.os.tag == .windows) {
        mod.linkSystemLibrary("ws2_32", .{});
        mod.linkSystemLibrary("crypt32", .{});
    }

    const example_step = create_example: {
        const example_option = b.option(Example, "example", "Example to run") orelse {
            const fail = b.addFail("Missing example, use -Dexample=<example name>!");
            break :create_example &fail.step;
        };

        const example_mod = b.addModule("zeppelin-example", .{
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{@tagName(example_option)})),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zeppelin", .module = mod },
            },
        });

        const example_exe = b.addExecutable(.{
            .name = "zeppelin-example",
            .root_module = example_mod,
        });

        const example_run = b.addRunArtifact(example_exe);

        break :create_example &example_run.step;
    };

    const build_example_step = b.step("run-example", "Run an example");
    build_example_step.dependOn(example_step);
}
