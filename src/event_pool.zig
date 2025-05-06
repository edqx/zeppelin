const std = @import("std");

const Client = @import("Client.zig");

pub fn EventPool(comptime Handler: type) type {
    return struct {
        const EventPoolT = @This();

        client: *Client,
        handler: *Handler,
        allocator: std.mem.Allocator,

        pub fn deinit(self: EventPoolT) void {
            _ = self;
        }

        pub fn start(self: EventPoolT) !void {
            while (true) {
                try self.client.receiveAndDispatch(self.handler);
            }
        }
    };
}
