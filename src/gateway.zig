const std = @import("std");
const builtin = @import("builtin");
const websocket = @import("websocket");

const gateway_message = @import("gateway_message.zig");

const log = std.log.scoped(.zeppelin_gateway);

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

const IntentInt = i32;

pub const Intent = packed struct(IntentInt) {
    guilds: bool = false,
    guild_members: bool = false,
    guild_moderation: bool = false,
    guild_expressions: bool = false,
    guild_integrations: bool = false,
    guild_webhooks: bool = false,
    guild_invites: bool = false,
    guild_voice_states: bool = false,
    guild_presences: bool = false,
    guild_messages: bool = false,
    guild_message_reactions: bool = false,
    guild_message_typing: bool = false,
    direct_messages: bool = false,
    direct_message_reactions: bool = false,
    direct_message_typing: bool = false,
    message_content: bool = false,
    guild_scheduled_events: bool = false,
    _padding1: enum(u3) { unset } = .unset,
    auto_moderation_configuration: bool = false,
    auto_moderation_execution: bool = false,
    _padding2: enum(u2) { unset } = .unset,
    guild_message_polls: bool = false,
    direct_message_polls: bool = false,
    _padding3: enum(u6) { unset } = .unset,

    pub const all: Intent = .{
        .guilds = true,
        .guild_members = false,
        .guild_moderation = true,
        .guild_expressions = true,
        .guild_integrations = true,
        .guild_webhooks = true,
        .guild_invites = true,
        .guild_voice_states = true,
        .guild_presences = false,
        .guild_messages = true,
        .guild_message_reactions = true,
        .guild_message_typing = true,
        .direct_messages = true,
        .direct_message_reactions = true,
        .direct_message_typing = true,
        .message_content = true,
        .guild_scheduled_events = true,
        .auto_moderation_configuration = true,
        .auto_moderation_execution = true,
        .guild_message_polls = true,
        .direct_message_polls = true,
    };
};

pub const MessageRead = union(enum) {
    pub const DispatchEvent = struct {
        name: []const u8,
        data_json: std.json.Value,
    };

    pub const Hello = struct {
        heartbeat_interval: usize,
    };

    dispatch_event: DispatchEvent,
    reconnect: void,
    invalid_session: void,
    hello: Hello,
    close: gateway_message.opcode.Close,
};

pub const Options = struct {
    intents: Intent,
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    websocket_client: websocket.Client,

    token_ephemeral: ?[]const u8,
    options: Options,

    heartbeat_reset: std.Thread.ResetEvent,
    heartbeat_thread: ?std.Thread,

    heartbeat_interval: ?usize,
    state: State,

    pub fn init(allocator: std.mem.Allocator, token_ephemeral: []const u8, options: Options) !Client {
        var websocket_client = try websocket.Client.init(allocator, .{
            .host = "gateway.discord.gg",
            .port = 443,
            .tls = true,
        });

        try websocket_client.handshake("/?v=10&encoding=json", .{
            .timeout_ms = 5000,
            .headers = "Host: gateway.discord.gg",
        });

        return .{
            .allocator = allocator,
            .websocket_client = websocket_client,

            .token_ephemeral = token_ephemeral,
            .options = options,

            .heartbeat_reset = .{},
            .heartbeat_thread = null,

            .heartbeat_interval = std.time.ms_per_s * 40,
            .state = .established,
        };
    }

    pub fn deinit(self: *Client) void {
        self.stopHeartbeat();
        self.websocket_client.deinit();
    }

    pub fn disconnect(self: *Client) !void {
        self.stopHeartbeat();
        try self.websocket_client.close(.{});
    }

    pub fn stopHeartbeat(self: *Client) void {
        if (self.heartbeat_thread) |thread| {
            self.heartbeat_reset.set();
            thread.join();
            self.heartbeat_thread = null;
        }
    }

    pub fn connectAndAuthenticate(self: *Client) !void {
        try self.websocket_client.readTimeout(0);

        while (true) {
            var arena: std.heap.ArenaAllocator = .init(self.allocator);
            defer arena.deinit();

            const allocator = arena.allocator();

            switch (try self.readMessage(allocator)) {
                .dispatch_event,
                .reconnect,
                .invalid_session,
                => {},
                .hello => |hello_details| {
                    self.heartbeat_interval = hello_details.heartbeat_interval;
                    self.heartbeat_thread = try std.Thread.spawn(.{}, heartbeatInterval, .{self});
                    self.state = .received_hello;

                    try self.sendIdentify(allocator);
                    break;
                },
                .close => return error.UnexpectedClose,
            }
        }
    }

    pub fn readMessage(self: *Client, arena: std.mem.Allocator) !MessageRead {
        var reader = &self.websocket_client._reader;

        while (true) {
            const message = try self.websocket_client.read() orelse unreachable;
            defer reader.done(message.type);

            switch (message.type) {
                .text, .binary => {
                    const event = try std.json.parseFromSliceLeaky(gateway_message.Receive, arena, message.data, .{
                        .allocate = .alloc_always,
                        .ignore_unknown_fields = true,
                    });

                    const opcode = std.meta.intToEnum(gateway_message.opcode.Receive, event.op) catch {
                        return error.UnknownOpcode;
                    };

                    switch (opcode) {
                        .dispatch => {
                            return .{ .dispatch_event = .{
                                .name = event.t.?,
                                .data_json = event.d.?,
                            } };
                        },
                        .heartbeat => {
                            // TODO: handle
                        },
                        .reconnect => {
                            return .reconnect;
                        },
                        .invalid_session => {
                            return .invalid_session;
                        },
                        .hello => {
                            const hello_payload = try std.json.parseFromValueLeaky(
                                gateway_message.payload.Hello,
                                arena,
                                event.d orelse .null,
                                .{
                                    .ignore_unknown_fields = true,
                                },
                            );
                            return .{ .hello = .{
                                .heartbeat_interval = @intCast(hello_payload.heartbeat_interval),
                            } };
                        },
                        .heartbeat_acknowledge => {
                            // TODO: dunno yet
                        },
                    }
                },
                .ping => {
                    try self.websocket_client.writeFrame(.pong, @constCast(message.data));
                },
                .close => {
                    if (message.data.len > 1) blk: {
                        const close_opcode_int = std.mem.readInt(u16, message.data[0..2], .big);

                        const close_opcode: gateway_message.opcode.Close = std.meta.intToEnum(gateway_message.opcode.Close, close_opcode_int) catch break :blk;

                        return .{ .close = close_opcode };
                    }

                    self.websocket_client.close(.{}) catch unreachable;
                },
                .pong => {},
            }
        }
    }

    fn sendEvent(
        self: *Client,
        allocator: std.mem.Allocator,
        comptime opcode: gateway_message.opcode.Send,
        payload: opcode.Payload(),
    ) !void {
        const send_event: gateway_message.Send(opcode.Payload()) = .{
            .op = @intFromEnum(opcode),
            .d = payload,
        };

        const data = try std.json.stringifyAlloc(allocator, send_event, .{});
        defer allocator.free(data);

        try self.websocket_client.write(data);
    }

    fn sendIdentify(self: *Client, allocator: std.mem.Allocator) !void {
        const token = self.token_ephemeral orelse {
            log.err("Expected token to be available for identify", .{});
            return;
        };
        self.token_ephemeral = null;

        try self.sendEvent(allocator, .identify, .{
            .token = token,
            .properties = .{
                .os = @tagName(builtin.os.tag),
                .browser = "zeppelin",
                .device = "zeppelin",
            },
            .intents = @bitCast(self.options.intents),
        });
    }

    fn heartbeatInterval(self: *Client) !void {
        while (true) {
            if (self.heartbeat_reset.timedWait(@intCast(std.time.ns_per_ms * self.heartbeat_interval.?))) {
                break; // no more heartbeats, gateway disconnected
            } else |e| {
                switch (e) {
                    error.Timeout => if (!self.state.alive()) continue,
                    else => return e,
                }
            }
        }
    }
};
