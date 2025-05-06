const std = @import("std");
const websocket = @import("websocket");
const gateway = @import("gateway.zig");

const Client = @This();

pub const InitOptions = struct {
    allocator: std.mem.Allocator,
};

allocator: std.mem.Allocator,
maybe_gateway_client: ?gateway.Client,

pub fn init(options: InitOptions) !Client {
    return .{
        .allocator = options.allocator,
        .maybe_gateway_client = null,
    };
}

pub fn deinit(self: *Client) void {
    if (self.maybe_gateway_client) |*gateway_client| {
        gateway_client.deinit();
    }
}

pub fn connectAndLogin(self: *Client, token: []const u8, options: gateway.Options) !void {
    self.maybe_gateway_client = @as(gateway.Client, undefined);
    try self.maybe_gateway_client.?.init(self.allocator, token, options);
    try self.maybe_gateway_client.?.connectAndAuthenticate();
}

pub fn receiveAndDispatch(self: *Client, handler: anytype) !void {
    _ = handler;

    const gateway_client: *gateway.Client = if (self.maybe_gateway_client) |*c| c else return error.NotConnected;

    while (true) {
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();

        const allocator = arena.allocator();

        const opcode, const event = try gateway_client.readEvent(allocator);

        switch (opcode) {
            .dispatch => {
                // todo: handle
                std.log.info("Got dispatch {}", .{event});
                break;
            },
            .heartbeat => {
                // todo: handle
            },
            .reconnect => {
                // todo: handle
            },
            .invalid_session => {
                // todo: handle
            },
            .hello => {
                // todo: error
            },
            .heartbeat_acknowledge => {
                // todo: dunno yet
            },
        }
    }
}
