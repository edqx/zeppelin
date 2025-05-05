const std = @import("std");
const websocket = @import("websocket");
const GatewayClient = @import("GatewayClient.zig");

const Client = @This();

const Options = struct {
    allocator: std.mem.Allocator,
};

allocator: std.mem.Allocator,
maybe_gateway_client: ?GatewayClient,

pub fn init(options: Options) !Client {
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

pub fn connectAndLogin(self: *Client, token: []const u8) !void {
    self.maybe_gateway_client = @as(GatewayClient, undefined);
    try self.maybe_gateway_client.?.init(token, self.allocator);
}
