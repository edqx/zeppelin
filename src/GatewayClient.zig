const std = @import("std");
const builtin = @import("builtin");
const websocket = @import("websocket");

const gateway_messages = @import("gateway_messages.zig");

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

allocator: std.mem.Allocator,
token: []const u8,
websocket_client: websocket.Client,

read_thread: std.Thread,
heartbeat_thread: ?std.Thread,

heartbeat_interval: ?usize,
state: State,

pub fn init(self: *GatewayClient, token: []const u8, allocator: std.mem.Allocator) !void {
    self.* = .{
        .allocator = allocator,
        .token = token,
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
}

pub fn deinit(self: *GatewayClient) void {
    self.websocket_client.deinit();
}

pub fn serverMessage(self: *GatewayClient, data: []u8) !void {
    log.info("Got {} bytes from Discord gateway: '''{s}'''", .{ data.len, data });

    var arena: std.heap.ArenaAllocator = .init(self.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const event = try std.json.parseFromSliceLeaky(gateway_messages.event.Receive, allocator, data, .{
        .ignore_unknown_fields = true,
    });

    const opcode = std.meta.intToEnum(gateway_messages.opcode.Receive, event.op) catch {
        std.log.err("Received unknown opcode from Gateway: {}", .{event.op});
        return;
    };

    switch (opcode) {
        .dispatch => {},
        .heartbeat => {},
        .invalid_session => {},
        .reconnect => {},
        .hello => {
            const hello_payload = try std.json.parseFromValueLeaky(gateway_messages.payload.Hello, allocator, event.d orelse .null, .{
                .ignore_unknown_fields = true,
            });
            try self.handleHello(allocator, hello_payload);
        },
        .heartbeat_acknowledge => {},
    }
}

fn handleHello(self: *GatewayClient, arena: std.mem.Allocator, hello_payload: gateway_messages.payload.Hello) !void {
    if (hello_payload.heartbeat_interval < 0) {
        std.log.err("Hello payload had invalid heartbeat interval: {}", .{hello_payload.heartbeat_interval});
        return;
    }
    self.heartbeat_interval = @intCast(hello_payload.heartbeat_interval);
    self.heartbeat_thread = try std.Thread.spawn(.{}, heartbeatInterval, .{self});
    self.state = .received_hello;

    try self.sendIdentify(arena);
}

fn sendEvent(
    self: *GatewayClient,
    allocator: std.mem.Allocator,
    comptime opcode: gateway_messages.opcode.Send,
    payload: opcode.Payload(),
) !void {
    const send_event: gateway_messages.event.Send(opcode.Payload()) = .{
        .op = @intFromEnum(opcode),
        .d = payload,
    };

    const data = try std.json.stringifyAlloc(allocator, send_event, .{});
    defer allocator.free(data);

    std.log.info("identify: {s}", .{data});

    try self.websocket_client.write(data);
}

fn sendIdentify(self: *GatewayClient, allocator: std.mem.Allocator) !void {
    try self.sendEvent(allocator, .identify, .{
        .token = self.token,
        .properties = .{
            .os = @tagName(builtin.os.tag),
            .browser = "zeppelin",
            .device = "zeppelin",
        },
        .intents = 0,
    });
}

fn heartbeatInterval(self: *GatewayClient) !void {
    while (true) {
        std.Thread.sleep(@intCast(std.time.ns_per_ms * self.heartbeat_interval.?));
        if (!self.state.alive()) continue;
    }
}
