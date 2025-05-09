const std = @import("std");
const websocket = @import("websocket");
const gateway = @import("gateway.zig");
const gateway_message = @import("gateway_message.zig");

const Cache = @import("cache.zig").Cache;

const Channel = @import("structures/Channel.zig");
const Guild = @import("structures/Guild.zig");
const Message = @import("structures/Message.zig");
const User = @import("structures/User.zig");

const Client = @This();

pub const InitOptions = struct {
    allocator: std.mem.Allocator,
};

pub const Event = union(enum) {
    pub const DispatchType = enum {
        ready,
        guild_create,
        message_create,
    };

    pub const Ready = struct {
        user: *User,
    };

    pub const GuildCreate = struct {
        guild: *Guild,
    };

    pub const MessageCreate = struct {
        message: *Message,
    };

    ready: Ready,
    guild_create: GuildCreate,
    message_create: MessageCreate,
};

pub const dispatch_event_map: std.StaticStringMap(Event.DispatchType) = .initComptime(.{
    .{ "READY", .ready },
    .{ "GUILD_CREATE", .guild_create },
    .{ "MESSAGE_CREATE", .message_create },
});

pub const GlobalCache = struct {
    channels: Cache(Channel, *Client),
    guilds: Cache(Guild, *Client),
    messages: Cache(Message, *Client),
    users: Cache(User, *Client),
};

allocator: std.mem.Allocator,
maybe_gateway_client: ?gateway.Client,

global_cache: GlobalCache,

pub fn init(options: InitOptions) !Client {
    return .{
        .allocator = options.allocator,
        .maybe_gateway_client = null,
        .global_cache = .{
            .channels = .init(options.allocator),
            .guilds = .init(options.allocator),
            .messages = .init(options.allocator),
            .users = .init(options.allocator),
        },
    };
}

pub fn deinit(self: *Client) void {
    if (self.maybe_gateway_client) |*gateway_client| {
        gateway_client.deinit();
    }
    self.global_cache.users.deinit();
    self.global_cache.messages.deinit();
}

pub fn connected(self: *Client) bool {
    return self.maybe_gateway_client != null;
}

pub fn disconnect(self: *Client) !void {
    var gateway_client: *gateway.Client = &(self.maybe_gateway_client orelse return error.NotConnected);

    try gateway_client.disconnect();
    gateway_client.deinit();
    self.maybe_gateway_client = null;
}

pub fn connectAndLogin(self: *Client, token: []const u8, options: gateway.Options) !void {
    if (self.maybe_gateway_client != null) return error.Connected;

    self.maybe_gateway_client = try gateway.Client.init(self.allocator, token, options);
    try self.maybe_gateway_client.?.connectAndAuthenticate();
}

fn processReadyEvent(self: *Client, allocator: std.mem.Allocator, json: std.json.Value) !Event.Ready {
    const ready_data = try std.json.parseFromValueLeaky(
        gateway_message.payload.Ready,
        allocator,
        json,
        .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        },
    );

    const user = try self.global_cache.users.patch(
        self,
        try .resolve(ready_data.user.id),
        ready_data.user,
    );

    return .{
        .user = user,
    };
}

fn processGuildCreate(self: *Client, allocator: std.mem.Allocator, json: std.json.Value) !Event.GuildCreate {
    const guild_data = try std.json.parseFromValueLeaky(
        gateway_message.payload.GuildCreate,
        allocator,
        json,
        .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        },
    );

    const guild = switch (guild_data) {
        .available => |available_data| try self.global_cache.guilds.patch(
            self,
            try .resolve(available_data.inner_guild.id),
            .{ .available = .{
                .base = available_data.inner_guild,
                .channels = available_data.extra.channels,
            } },
        ),
        .unavailable => |unavailable_data| try self.global_cache.guilds.patch(
            self,
            try .resolve(unavailable_data.id),
            .{ .unavailable = unavailable_data },
        ),
    };

    return .{ .guild = guild };
}

fn processMessageCreate(self: *Client, allocator: std.mem.Allocator, json: std.json.Value) !Event.MessageCreate {
    const message_data = try std.json.parseFromValueLeaky(
        gateway_message.payload.MessageCreate,
        allocator,
        json,
        .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        },
    );

    const message = try self.global_cache.messages.patch(
        self,
        try .resolve(message_data.inner_message.id),
        message_data.inner_message,
    );

    return .{
        .message = message,
    };
}

pub fn receive(self: *Client) !Event {
    const gateway_client: *gateway.Client = &(self.maybe_gateway_client orelse return error.NotConnected);

    while (true) {
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();

        const allocator = arena.allocator();

        switch (try gateway_client.readMessage(allocator)) {
            .dispatch_event => |dispatch_event| {
                const dispatch_event_type = dispatch_event_map.get(dispatch_event.name) orelse continue;

                switch (dispatch_event_type) {
                    .ready => {
                        return .{ .ready = try self.processReadyEvent(allocator, dispatch_event.data_json) };
                    },
                    .guild_create => {
                        return .{ .guild_create = try self.processGuildCreate(allocator, dispatch_event.data_json) };
                    },
                    .message_create => {
                        return .{ .message_create = try self.processMessageCreate(allocator, dispatch_event.data_json) };
                    },
                }
            },
            .hello, .invalid_session, .reconnect => {
                // TODO: handle
            },
            .close => |close_opcode| {
                switch (close_opcode) {
                    .rate_limited => return error.RateLimited,
                    .session_timed_out => return error.TimedOut,
                    .not_authenticated,
                    .authentication_failed,
                    .already_authenticated,
                    => return error.AuthenticationFailed,
                    .invalid_intents,
                    .disallowed_intents,
                    => return error.BadIntents,
                    .unknown_error,
                    .unknown_opcode,
                    .decode_error,
                    .invalid_sequence,
                    .invalid_shard,
                    .sharding_required,
                    .invalid_api_version,
                    => return error.UnexpectedClose,
                }
            },
        }
    }
}

pub fn receiveAndDispatch(self: *Client, handler: anytype) !void {
    const event = try self.receive();

    switch (event) {
        .ready => |ev| if (@hasDecl(@TypeOf(handler.*), "ready")) try handler.ready(ev),
        .guild_create => |ev| if (@hasDecl(@TypeOf(handler.*), "guildCreate")) try handler.guildCreate(ev),
        .message_create => |ev| if (@hasDecl(@TypeOf(handler.*), "messageCreate")) try handler.messageCreate(ev),
    }
}
