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
}

pub fn receiveAndDispatch(self: *Client, handler: anytype) !void {
    _ = self;
    _ = handler;
}
