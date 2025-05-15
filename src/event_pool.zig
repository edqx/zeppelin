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
                if (!self.client.connected()) break;

                self.client.receiveAndDispatch(self.handler) catch |e| switch (e) {
                    error.RateLimited,
                    error.TimedOut,
                    error.AuthenticationFailed,
                    error.BadIntents,
                    error.UnexpectedClose,
                    => {
                        if (self.client.maybe_reconnect_options) |reconnect_options| {
                            try self.client.connectAndLogin(reconnect_options);
                        } else {
                            return e;
                        }
                    },
                    else => return e,
                };
            }
        }
    };
}
