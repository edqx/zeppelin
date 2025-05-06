const std = @import("std");
const builtin = @import("builtin");
const websocket = @import("websocket");

const gateway_messages = @import("gateway_messages.zig");

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
    auto_moderation_configuration: bool = false,
    _padding1: enum(u3) { unset } = .unset,
    auto_moderation_execution: bool = false,
    _padding2: enum(u2) { unset } = .unset,
    guild_message_polls: bool = false,
    direct_message_polls: bool = false,
    _padding3: enum(u6) { unset } = .unset,

    pub const all: Intent = .{
        .guilds = true,
        .guild_members = true,
        .guild_moderation = true,
        .guild_expressions = true,
        .guild_integrations = true,
        .guild_webhooks = true,
        .guild_invites = true,
        .guild_voice_states = true,
        .guild_presences = true,
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

pub const Options = struct {
    intents: Intent,
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    websocket_client: websocket.Client,

    token_ephemeral: ?[]const u8,
    options: Options,

    read_thread: std.Thread,
    heartbeat_thread: ?std.Thread,

    heartbeat_interval: ?usize,
    state: State,

    pub fn init(self: *Client, allocator: std.mem.Allocator, token_ephemeral: []const u8, options: Options) !void {
        self.* = .{
            .allocator = allocator,
            .websocket_client = undefined,

            .token_ephemeral = token_ephemeral,
            .options = options,

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

    pub fn deinit(self: *Client) void {
        self.websocket_client.deinit();
    }

    pub fn serverMessage(self: *Client, data: []u8) !void {
        log.info("Got {} bytes from Discord gateway: '''{s}'''", .{ data.len, data });

        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();

        const allocator = arena.allocator();

        const event = try std.json.parseFromSliceLeaky(gateway_messages.event.Receive, allocator, data, .{
            .ignore_unknown_fields = true,
        });

        const opcode = std.meta.intToEnum(gateway_messages.opcode.Receive, event.op) catch {
            log.err("Received unknown opcode from Gateway: {}", .{event.op});
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

    fn handleHello(self: *Client, arena: std.mem.Allocator, hello_payload: gateway_messages.payload.Hello) !void {
        if (hello_payload.heartbeat_interval < 0) {
            log.err("Hello payload had invalid heartbeat interval: {}", .{hello_payload.heartbeat_interval});
            return;
        }
        self.heartbeat_interval = @intCast(hello_payload.heartbeat_interval);
        self.heartbeat_thread = try std.Thread.spawn(.{}, heartbeatInterval, .{self});
        self.state = .received_hello;

        try self.sendIdentify(arena);
    }

    fn sendEvent(
        self: *Client,
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

        log.info("identify: {s}", .{data});

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
            std.Thread.sleep(@intCast(std.time.ns_per_ms * self.heartbeat_interval.?));
            if (!self.state.alive()) continue;
        }
    }
};
