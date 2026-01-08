const std = @import("std");

const log = @import("log.zig").zeppelin;

const Client = @import("Client.zig");

pub fn EventPool(comptime Handler: type) type {
    return struct {
        const EventPoolT = @This();

        allocator: std.mem.Allocator,

        client: *Client,
        handler: *Handler,

        // thread_pool: std.Thread.Pool,

        pub fn init(self: *EventPoolT, allocator: std.mem.Allocator, client: *Client, handler: *Handler) !void {
            self.* = .{
                .allocator = allocator,
                .client = client,
                .handler = handler,
                // .thread_pool = undefined,
            };

            // try self.thread_pool.init(.{
            //     .allocator = allocator,
            // });
        }

        pub fn deinit(self: *EventPoolT) void {
            // self.thread_pool.deinit();
            _ = self;
        }

        // pub fn dispatchThreadImpl(self: *EventPoolT, arena: *std.heap.ArenaAllocator, event: Client.Event) !void {
        //     defer self.allocator.destroy(arena);
        //     defer arena.deinit();
        //     try Client.Event.dispatch(event, self.handler);
        // }

        // pub fn dispatchThread(self: *EventPoolT, arena: *std.heap.ArenaAllocator, event: Client.Event) void {
        //     self.dispatchThreadImpl(arena, event) catch |err| {
        //         std.log.err("{s}", .{@errorName(err)});
        //         if (@errorReturnTrace()) |trace| {
        //             std.debug.dumpStackTrace(trace.*);
        //         }
        //     };
        // }

        pub fn start(self: *EventPoolT) !void {
            var arena: std.heap.ArenaAllocator = .init(self.allocator);
            defer arena.deinit();

            while (true) {
                if (!self.client.connected()) break;

                // const arena = try self.allocator.create(std.heap.ArenaAllocator);
                // errdefer self.allocator.destroy(arena);

                // arena.* = .init(self.allocator);
                // errdefer arena.deinit();

                const event = self.client.receive(&arena) catch |e| switch (e) {
                    error.Disconnected => {
                        if (self.client.takeReconnect()) |options| {
                            defer self.client.freeReconnect(options);
                            try self.client.connectAndLogin(options);
                            continue;
                        } else {
                            return error.Disconnected;
                        }
                    },
                    else => return e,
                };

                try Client.Event.dispatch(event, self.handler);

                // try self.thread_pool.spawn(dispatchThread, .{ self, arena, event });
            }
        }
    };
}
