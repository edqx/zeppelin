const std = @import("std");

pub fn EventPool(comptime Handler: type) type {
    return struct {
        const EventPoolT = @This();

        handler: *Handler,
        allocator: std.mem.Allocator,

        pub fn deinit(self: EventPoolT) void {
            _ = self;
        }

        pub fn start(self: EventPoolT) !void {
            _ = self;

            while (true) {}
        }
    };
}
