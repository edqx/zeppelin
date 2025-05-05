const std = @import("std");
const builtin = @import("builtin");

const zeppelin = @import("zeppelin");

const use_gpa = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;

pub fn main() !void {
    var gpa = if (use_gpa) std.heap.GeneralPurposeAllocator(.{}){} else {};
    defer if (use_gpa) std.debug.assert(gpa.deinit() == .ok);

    const allocator = if (use_gpa) gpa.allocator() else std.heap.c_allocator;

    var client: zeppelin.Client = try .init(.{
        .allocator = allocator,
    });
    defer client.deinit();

    try client.connectAndLogin("");

    while (true) {}
}
