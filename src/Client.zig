const std = @import("std");
const websocket = @import("websocket");

const gateway = @import("gateway.zig");
const gateway_message = @import("gateway_message.zig");
const endpoints = @import("constants.zig").endpoints;

const Snowflake = @import("snowflake.zig").Snowflake;

const Authentication = @import("authentication.zig").Authentication;
const Cache = @import("cache.zig").Cache;

const Rest = @import("Rest.zig");

const Channel = @import("structures/Channel.zig");
const Guild = @import("structures/Guild.zig");
const Message = @import("structures/Message.zig");
const Role = @import("structures/Role.zig");
const User = @import("structures/User.zig");

const Client = @This();

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
    roles: Cache(Role, *Client),
    users: Cache(User, *Client),
};

pub const InitOptions = struct {
    allocator: std.mem.Allocator,
    authentication: Authentication,
};

allocator: std.mem.Allocator,
maybe_gateway_client: ?gateway.Client,
maybe_reconnect_options: ?gateway.Options,

rest_client: Rest,

global_cache: GlobalCache,

pub fn init(options: InitOptions) !Client {
    return .{
        .allocator = options.allocator,
        .maybe_gateway_client = null,
        .maybe_reconnect_options = null,
        .rest_client = .init(options.allocator, options.authentication),
        .global_cache = .{
            .channels = .init(options.allocator),
            .guilds = .init(options.allocator),
            .messages = .init(options.allocator),
            .roles = .init(options.allocator),
            .users = .init(options.allocator),
        },
    };
}

pub fn deinit(self: *Client) void {
    self.global_cache.users.deinit();
    self.global_cache.roles.deinit();
    self.global_cache.messages.deinit();
    self.global_cache.guilds.deinit();
    self.global_cache.channels.deinit();
    self.rest_client.deinit();
    self.clearReconnect();
    if (self.maybe_gateway_client) |*gateway_client| {
        gateway_client.deinit();
    }
}

pub fn connected(self: *Client) bool {
    return self.maybe_gateway_client != null;
}

pub fn disconnect(self: *Client) !void {
    var gateway_client: *gateway.Client = &(self.maybe_gateway_client orelse return error.NotConnected);

    try gateway_client.disconnect();
    gateway_client.deinit();
    self.maybe_gateway_client = null;
    self.clearReconnect();
}

pub fn connectAndLogin(self: *Client, options: gateway.Options) !void {
    if (self.maybe_gateway_client != null) return error.Connected;
    self.maybe_reconnect_options = null;

    self.maybe_gateway_client = try gateway.Client.init(
        self.allocator,
        self.rest_client.authentication.resolve(),
        options,
    );
    try self.maybe_gateway_client.?.connectAndAuthenticate();
}

fn clearReconnect(self: *Client) void {
    if (self.maybe_reconnect_options) |reconnect_options| {
        self.allocator.free(reconnect_options.session_id);
        self.allocator.free(reconnect_options.host);
    }
    self.maybe_reconnect_options = null;
}

fn processReadyEvent(self: *Client, arena: std.mem.Allocator, json: std.json.Value) !Event.Ready {
    const ready_data = try std.json.parseFromValueLeaky(
        gateway_message.payload.Ready,
        arena,
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

    const session_id = try self.allocator.dupe(u8, ready_data.session_id);
    errdefer self.allocator.free(session_id);
    const resume_gateway_url = try self.allocator.dupe(u8, ready_data.resume_gateway_url);
    errdefer self.allocator.free(resume_gateway_url);

    self.maybe_reconnect_options = self.maybe_gateway_client.?.options;
    self.maybe_reconnect_options.?.session_id = session_id;
    self.maybe_reconnect_options.?.host = resume_gateway_url;

    return .{ .user = user };
}

fn processGuildCreate(self: *Client, arena: std.mem.Allocator, json: std.json.Value) !Event.GuildCreate {
    const guild_data = try std.json.parseFromValueLeaky(
        gateway_message.payload.GuildCreate,
        arena,
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
                .members = available_data.extra.members,
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

fn processMessageCreate(self: *Client, arena: std.mem.Allocator, json: std.json.Value) !Event.MessageCreate {
    const message_data = try std.json.parseFromValueLeaky(
        gateway_message.payload.MessageCreate,
        arena,
        json,
        .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        },
    );

    const message = try self.global_cache.messages.patch(
        self,
        try .resolve(message_data.inner_message.id),
        .{
            .base = message_data.inner_message,
            .guild_id = switch (message_data.extra.guild_id) {
                .not_given => null,
                .val => |guild_id| guild_id,
            },
            .member = switch (message_data.extra.member) {
                .not_given => null,
                .val => |member| member,
            },
            .mentions = message_data.extra.mentions,
        },
    );

    return .{ .message = message };
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
            .close => |maybe_close_opcode| {
                if (maybe_close_opcode) |close_opcode| {
                    if (!close_opcode.reconnect()) {
                        self.clearReconnect();
                    }

                    try self.disconnect();

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
                } else {
                    self.clearReconnect();
                    return error.UnexpectedClose;
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

pub fn createMessage(self: *Client, channel_id: Snowflake, content: []const u8) !*Message {
    var req = try self.rest_client.create(.POST, endpoints.create_message, .{
        .channel_id = channel_id,
    });
    defer req.deinit();

    var json_writer = try req.begin(.json);

    try json_writer.beginObject();

    try json_writer.objectField("content");
    try json_writer.write(content);

    try json_writer.endObject();

    const message_response = try req.fetchJson(gateway_message.Message);
    return try self.global_cache.messages.patch(self, try .resolve(message_response.id), .{
        .base = message_response,
        .guild_id = null,
        .member = null,
        .mentions = &.{},
    });
}
