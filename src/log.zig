const std = @import("std");

const build_options = @import("build_options");

pub fn noop(comptime format: []const u8, args: anytype) void {
    _ = format;
    _ = args;
}

pub const zeppelin = if (build_options.logging) std.log.scoped(.zeppelin) else struct {
    pub const err = noop;
    pub const warn = noop;
    pub const info = noop;
    pub const debug = noop;
};
