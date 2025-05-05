const std = @import("std");
const websocket = @import("websocket");

const log = std.log.scoped(.zeppelin_gateway);

const GatewayClient = @This();

pub const State = enum {
    established,
    received_hello,
    sent_identify,
    ready,
    disconnect,

    pub fn alive(self: State) bool {
        return switch (self) {
            .received_hello, .sent_identify, .ready => true,
            .established, .disconnect => false,
        };
    }
};

websocket_client: websocket.Client,

read_thread: std.Thread,
heartbeat_thread: std.Thread,

heartbeat_interval: usize,
state: State,

pub fn init(self: *GatewayClient, allocator: std.mem.Allocator) !void {
    self.* = .{
        .websocket_client = undefined,

        .read_thread = undefined,
        .heartbeat_thread = undefined,

        .heartbeat_interval = std.time.ms_per_s * 40,
        .state = .established,
    };

    self.websocket_client = try websocket.Client.init(allocator, .{
        .host = "gateway.discord.gg",
        .port = 443,
        .tls = true,
    });

    try self.websocket_client.handshake("/?v=10&encoding=json", .{
        .timeout_ms = 5000,
        .headers = "Host: gateway.discord.gg",
    });

    self.read_thread = try self.websocket_client.readLoopInNewThread(self);
    self.heartbeat_thread = try std.Thread.spawn(.{}, heartbeatInterval, .{self});
}

pub fn deinit(self: *GatewayClient) void {
    self.websocket_client.deinit();
}

pub fn serverMessage(self: *GatewayClient, data: []u8) !void {
    _ = self;

    log.info("Got {} bytes from Discord gateway: '''{s}'''", .{ data.len, data });
}

pub fn heartbeatInterval(self: *GatewayClient) !void {
    while (true) {
        std.Thread.sleep(@intCast(std.time.ns_per_ms * self.heartbeat_interval));
        if (!self.state.alive()) continue;
    }
}
