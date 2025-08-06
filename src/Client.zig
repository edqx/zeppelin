const std = @import("std");
const websocket = @import("websocket");
const wardrobe = @import("wardrobe");

const log = @import("log.zig").zeppelin;

const gateway = @import("gateway.zig");
const gateway_message = @import("gateway_message.zig");
const endpoints = @import("constants.zig").endpoints;

const Snowflake = @import("snowflake.zig").Snowflake;

const Authentication = @import("authentication.zig").Authentication;

const Cache = @import("cache.zig").Cache;
const Pool = @import("cache.zig").Pool;

const MessageBuilder = @import("MessageBuilder.zig");
const ApplicationCommandBuilder = @import("ApplicationCommandBuilder.zig");

const Rest = @import("Rest.zig");

const Channel = @import("structures/Channel.zig");
const Guild = @import("structures/Guild.zig");
const Interaction = @import("structures/ephemeral/Interaction.zig");
const Message = @import("structures/Message.zig");
const Role = @import("structures/Role.zig");
const User = @import("structures/User.zig");

const StandardGatewayClient = gateway.Client(.{ .compression = .none });

const Client = @This();

pub const DispatchType = enum {
    ready,
    user_update,
    guild_create,
    guild_member_add,
    guild_member_remove,
    guild_member_update,
    message_create,
    message_delete,
    message_update,
    interaction_create,
};

pub const Event = union(DispatchType) {
    pub const Ready = struct {
        arena: std.mem.Allocator,
        user: *User,
    };

    pub const UserUpdate = struct {
        arena: std.mem.Allocator,
        user: *User,
    };

    pub const GuildCreate = struct {
        arena: std.mem.Allocator,
        guild: *Guild,
    };

    pub const GuildMemberAdd = struct {
        arena: std.mem.Allocator,
        guild: *Guild,
        guild_member: *Guild.Member,
    };

    pub const GuildMemberRemove = struct {
        arena: std.mem.Allocator,
        guild: *Guild,
        guild_member: *Guild.Member,
    };

    pub const GuildMemberUpdate = struct {
        arena: std.mem.Allocator,
        guild: *Guild,
        guild_member: *Guild.Member,
    };

    pub const MessageCreate = struct {
        arena: std.mem.Allocator,
        message: *Message,
    };

    pub const MessageDelete = struct {
        arena: std.mem.Allocator,
        message: *Message,
    };

    pub const MessageUpdate = struct {
        arena: std.mem.Allocator,
        message: *Message,
    };

    pub const InteractionCreate = struct {
        arena: std.mem.Allocator,
        interaction: Interaction,
        token: []const u8,
    };

    ready: Ready,
    user_update: UserUpdate,
    guild_create: GuildCreate,
    guild_member_add: GuildMemberAdd,
    guild_member_remove: GuildMemberRemove,
    guild_member_update: GuildMemberUpdate,
    message_create: MessageCreate,
    message_delete: MessageDelete,
    message_update: MessageUpdate,
    interaction_create: InteractionCreate,

    pub const dispatch_id_map: std.StaticStringMap(DispatchType) = .initComptime(.{
        .{ "READY", .ready },
        .{ "USER_UPDATE", .user_update },
        .{ "GUILD_CREATE", .guild_create },
        .{ "GUILD_MEMBER_ADD", .guild_member_add },
        .{ "GUILD_MEMBER_REMOVE", .guild_member_remove },
        .{ "GUILD_MEMBER_UPDATE", .guild_member_update },
        .{ "MESSAGE_CREATE", .message_create },
        .{ "MESSAGE_DELETE", .message_delete },
        .{ "MESSAGE_UPDATE", .message_update },
        .{ "INTERACTION_CREATE", .interaction_create },
    });

    pub fn handlerFunctionName(comptime dispatch_type: DispatchType) []const u8 {
        return switch (dispatch_type) {
            .ready => "ready",
            .user_update => "userUpdate",
            .guild_create => "guildCreate",
            .guild_member_add => "guildMemberAdd",
            .guild_member_remove => "guildMemberRemove",
            .guild_member_update => "guildMemberUpdate",
            .message_create => "messageCreate",
            .message_delete => "messageDelete",
            .message_update => "messageUpdate",
            .interaction_create => "interactionCreate",
        };
    }

    pub fn dispatch(event: Event, handler: anytype) !void {
        switch (event) {
            inline else => |ev, tag| {
                const handlerName = comptime handlerFunctionName(tag);
                if (@hasDecl(@TypeOf(handler.*), handlerName)) {
                    try @field(@TypeOf(handler.*), handlerName)(handler, ev);
                }
            },
        }
    }
};

pub const ChannelManager = struct {
    client: *Client,

    cache: Cache(Channel),
    pool: Pool(Channel),

    pub fn init(client: *Client) ChannelManager {
        return .{ .client = client, .cache = .init(client.allocator), .pool = .init(client.allocator) };
    }

    pub fn deinit(self: *ChannelManager) void {
        self.pool.deinit();
        self.cache.deinit();
    }

    pub fn getOrFetch(self: *ChannelManager, id: Snowflake) !?*Channel {
        return self.get(id) orelse try self.fetch(id);
    }

    pub fn get(self: *ChannelManager, id: Snowflake) ?*Channel {
        return self.pool.get(id);
    }

    pub fn fetch(self: *ChannelManager, id: Snowflake) !?*Channel {
        var req = try self.client.rest_client.create(.GET, endpoints.get_channel, .{
            .channel_id = id,
        });
        errdefer req.deinit();

        const channel_response = try req.fetchJson(gateway_message.Channel);
        const channel = try self.cache.patch(self.client, try .resolve(channel_response.id), channel_response);
        try self.pool.add(channel);
        return channel;
    }
};

pub const GuildManager = struct {
    client: *Client,

    cache: Cache(Guild),
    pool: Pool(Guild),

    pub fn init(client: *Client) GuildManager {
        return .{ .client = client, .cache = .init(client.allocator), .pool = .init(client.allocator) };
    }

    pub fn deinit(self: *GuildManager) void {
        self.pool.deinit();
        self.cache.deinit();
    }

    pub fn getOrFetch(self: *GuildManager, id: Snowflake) !?*Guild {
        return self.get(id) orelse try self.fetch(id);
    }

    pub fn get(self: *GuildManager, id: Snowflake) ?*Guild {
        return self.pool.get(id);
    }

    pub fn fetch(self: *GuildManager, id: Snowflake) !?*Guild {
        var req = try self.client.rest_client.create(.GET, endpoints.get_guild, .{
            .guild_id = id,
        });
        errdefer req.deinit();

        const guild_response = try req.fetchJson(gateway_message.Guild);
        const guild = try self.cache.patch(self.client, try .resolve(guild_response.id), .{
            .available = .{
                .base = guild_response,
                .channels = null,
                .members = null,
            },
        });
        try self.pool.add(guild);
        return guild;
    }
};

pub const MessageManager = struct {
    client: *Client,

    cache: Cache(Message),
    pool: Pool(Message),

    pub fn init(client: *Client) MessageManager {
        return .{ .client = client, .cache = .init(client.allocator), .pool = .init(client.allocator) };
    }

    pub fn deinit(self: *MessageManager) void {
        self.pool.deinit();
        self.cache.deinit();
    }

    pub fn getOrFetch(self: *MessageManager, id: Snowflake) !?*Message {
        return self.get(id) orelse try self.fetch(id);
    }

    pub fn get(self: *MessageManager, id: Snowflake) ?*Message {
        return self.pool.get(id);
    }

    pub fn fetch(self: *MessageManager, channel_id: Snowflake, id: Snowflake) !?*Message {
        var req = try self.client.rest_client.create(.GET, endpoints.get_channel_message, .{
            .channel_id = channel_id,
            .message_id = id,
        });
        errdefer req.deinit();

        const message_response = try req.fetchJson(gateway_message.Message);
        const message = try self.cache.patch(self.client, try .resolve(message_response.id), .{
            .base = message_response,
            .guild_id = null,
            .member = null,
            .mentions = null,
        });
        try self.pool.add(message);
        return message;
    }
};

pub const RoleManager = struct {
    client: *Client,

    cache: Cache(Role),
    pool: Pool(Role),

    pub fn init(client: *Client) RoleManager {
        return .{ .client = client, .cache = .init(client.allocator), .pool = .init(client.allocator) };
    }

    pub fn deinit(self: *RoleManager) void {
        self.pool.deinit();
        self.cache.deinit();
    }

    pub fn getOrFetch(self: *RoleManager, id: Snowflake) !?*Message {
        return self.get(id) orelse try self.fetch(id);
    }

    pub fn get(self: *RoleManager, id: Snowflake) ?*Message {
        return self.pool.get(id);
    }

    pub fn fetch(self: *RoleManager, guild_id: Snowflake, id: Snowflake) !?*Role {
        const guild = try self.client.guilds.cache.touch(self.client, id);

        var req = try self.client.rest_client.create(.GET, endpoints.get_guild_role, .{
            .guild_id = guild_id,
            .role_id = id,
        });
        errdefer req.deinit();

        const role_response = try req.fetchJson(gateway_message.Role);
        const role = try self.cache.patch(self.client, try .resolve(role_response.id), role_response);
        role.meta.patch(.guild, guild);
        try self.pool.add(role);
        return role;
    }
};

pub const UserManager = struct {
    client: *Client,

    cache: Cache(User),

    pub fn init(client: *Client) UserManager {
        return .{ .client = client, .cache = .init(client.allocator) };
    }

    pub fn deinit(self: *UserManager) void {
        self.cache.deinit();
    }

    pub fn getOrFetch(self: *UserManager, id: Snowflake) !?*User {
        return self.get(id) orelse try self.fetch(id);
    }

    pub fn get(self: *UserManager, id: Snowflake) ?*User {
        return self.pool.get(id);
    }

    pub fn fetch(self: *UserManager, id: Snowflake) !?*User {
        var req = try self.client.rest_client.create(.GET, endpoints.get_user, .{
            .user_id = id,
        });
        errdefer req.deinit();

        const user_response = try req.fetchJson(gateway_message.User);
        const user = try self.cache.patch(self.client, try .resolve(user_response.id), user_response);
        return user;
    }
};

pub const InitOptions = struct {
    allocator: std.mem.Allocator,
    authentication: Authentication,
};

allocator: std.mem.Allocator,
maybe_gateway_client: ?StandardGatewayClient,
maybe_reconnect_options: ?gateway.Options,

rest_client: Rest,

channels: ChannelManager,
guilds: GuildManager,
messages: MessageManager,
roles: RoleManager,
users: UserManager,

pub fn init(self: *Client, options: InitOptions) !void {
    self.* = .{
        .allocator = options.allocator,
        .maybe_gateway_client = null,
        .maybe_reconnect_options = null,
        .rest_client = .init(options.allocator, options.authentication),
        .channels = undefined,
        .guilds = undefined,
        .messages = undefined,
        .roles = undefined,
        .users = undefined,
    };

    self.channels = .init(self);
    self.guilds = .init(self);
    self.messages = .init(self);
    self.roles = .init(self);
    self.users = .init(self);
}

pub fn deinit(self: *Client) void {
    self.users.deinit();
    self.roles.deinit();
    self.messages.deinit();
    self.guilds.deinit();
    self.channels.deinit();
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
    var gateway_client: *StandardGatewayClient = &(self.maybe_gateway_client orelse return error.NotConnected);

    log.info("Disconnect requested", .{});

    self.clearReconnect();
    try gateway_client.disconnect();
}

pub fn connectAndLogin(self: *Client, options: gateway.Options) !void {
    if (self.maybe_gateway_client != null) return error.Connected;
    self.maybe_reconnect_options = null;

    self.maybe_gateway_client = @as(StandardGatewayClient, undefined);

    try StandardGatewayClient.init(
        &self.maybe_gateway_client.?,
        self.allocator,
        self.rest_client.authentication.resolve(),
        options,
    );
    if (try self.maybe_gateway_client.?.connectAndAuthenticate()) |fail_message| {
        switch (fail_message) {
            .dispatch_event, .hello, .close => unreachable,
            .reconnect => {
                try self.disconnect();
                return try self.connectAndLogin(options);
            },
            .invalid_session => {
                // todo: handle
            },
        }
    }
}

fn clearReconnect(self: *Client) void {
    if (self.maybe_reconnect_options) |reconnect_options| {
        self.allocator.free(reconnect_options.session_id);
        self.allocator.free(reconnect_options.host);
    }
    self.maybe_reconnect_options = null;
}

fn processReadyEvent(
    self: *Client,
    arena: std.mem.Allocator,
    data: gateway_message.payload.Ready,
) !Event.Ready {
    const user = try self.users.cache.patch(
        self,
        try .resolve(data.user.id),
        data.user,
    );

    log.info("User received, logged in as '{s}#{s}'", .{ user.username, user.discriminator });

    const session_id = try self.allocator.dupe(u8, data.session_id);
    errdefer self.allocator.free(session_id);
    const resume_gateway_url = try self.allocator.dupe(u8, data.resume_gateway_url);
    errdefer self.allocator.free(resume_gateway_url);

    self.maybe_reconnect_options = try self.maybe_gateway_client.?.options.dupe(self.allocator);
    self.maybe_reconnect_options.?.session_id = session_id;
    self.maybe_reconnect_options.?.host = resume_gateway_url;

    return .{ .arena = arena, .user = user };
}

fn processUserUpdate(
    self: *Client,
    arena: std.mem.Allocator,
    data: gateway_message.payload.UserUpdate,
) !Event.UserUpdate {
    const user = try self.users.cache.patch(
        self,
        try .resolve(data.id),
        data,
    );

    return .{ .arena = arena, .user = user };
}

fn processGuildCreate(
    self: *Client,
    arena: std.mem.Allocator,
    data: gateway_message.payload.GuildCreate,
) !Event.GuildCreate {
    const guild = switch (data) {
        .available => |available_data| try self.guilds.cache.patch(
            self,
            try .resolve(available_data.inner_guild.id),
            .{ .available = .{
                .base = available_data.inner_guild,
                .channels = available_data.extra.channels,
                .members = available_data.extra.members,
            } },
        ),
        .unavailable => |unavailable_data| try self.guilds.cache.patch(
            self,
            try .resolve(unavailable_data.id),
            .{ .unavailable = unavailable_data },
        ),
    };
    try self.guilds.pool.add(guild);

    return .{ .arena = arena, .guild = guild };
}

fn processGuildMemberAdd(
    self: *Client,
    arena: std.mem.Allocator,
    data: gateway_message.payload.GuildMemberAdd,
) !Event.GuildMemberAdd {
    const users_cache = &self.users.cache;
    const guilds_cache = &self.guilds.cache;

    const guild_id = data.extra.guild_id;
    const guild_member_data = data.inner_guild_member;

    switch (guild_member_data.user) {
        .not_given => {
            return error.NoGuildUser;
        }, // what can we do with a guild member with no user?
        .val => |user_data| {
            const user = try users_cache.patch(self, try .resolve(user_data.id), user_data);
            const guild = try guilds_cache.touch(self, try .resolve(guild_id));
            const guild_member = try guild.members.cache.patch(guild, user.id, guild_member_data);
            try guild.members.pool.add(guild_member);

            return .{ .arena = arena, .guild = guild, .guild_member = guild_member };
        },
    }
    unreachable;
}

fn processGuildMemberRemove(
    self: *Client,
    arena: std.mem.Allocator,
    data: gateway_message.payload.GuildMemberRemove,
) !Event.GuildMemberRemove {
    const users_cache = &self.users.cache;
    const guilds_cache = &self.guilds.cache;

    const guild = try guilds_cache.touch(self, try .resolve(data.guild_id));

    const user = try users_cache.patch(self, try .resolve(data.user.id), data.user);
    const guild_member = try guild.members.cache.touch(guild, try .resolve(data.user.id));
    guild.members.pool.remove(try .resolve(data.user.id));
    guild_member.meta.patch(.user, user);

    return .{ .arena = arena, .guild = guild, .guild_member = guild_member };
}

pub fn processGuildMemberUpdate(
    self: *Client,
    arena: std.mem.Allocator,
    data: gateway_message.payload.GuildMemberUpdate,
) !Event.GuildMemberUpdate {
    const user = try self.users.cache.patch(self, try .resolve(data.user.id), data.user);
    const guild = try self.guilds.cache.touch(self, try .resolve(data.guild_id));

    const guild_member = try guild.members.cache.touch(guild, user.id);
    try guild_member.patchUpdate(data);

    return .{ .arena = arena, .guild = guild, .guild_member = guild_member };
}

fn processMessageCreate(
    self: *Client,
    arena: std.mem.Allocator,
    data: gateway_message.payload.MessageCreate,
) !Event.MessageCreate {
    const message = try self.messages.cache.patch(
        self,
        try .resolve(data.inner_message.id),
        .{
            .base = data.inner_message,
            .guild_id = switch (data.extra.guild_id) {
                .not_given => null,
                .val => |guild_id| guild_id,
            },
            .member = switch (data.extra.member) {
                .not_given => null,
                .val => |member| member,
            },
            .mentions = data.extra.mentions,
        },
    );
    try self.messages.pool.add(message);

    return .{ .arena = arena, .message = message };
}

fn processMessageDelete(
    self: *Client,
    arena: std.mem.Allocator,
    data: gateway_message.payload.MessageDelete,
) !Event.MessageDelete {
    const message = try self.messages.cache.touch(self, try .resolve(data.id));
    const channel = try self.channels.cache.touch(self, try .resolve(data.channel_id));

    message.meta.patch(.channel, channel);
    switch (data.guild_id) {
        .not_given => {},
        .val => |guild_id| message.meta.patch(.guild, try self.guilds.cache.touch(self, try .resolve(guild_id))),
    }
    self.messages.pool.remove(try .resolve(data.id));

    return .{ .arena = arena, .message = message };
}

fn processMessageUpdate(
    self: *Client,
    arena: std.mem.Allocator,
    data: gateway_message.payload.MessageUpdate,
) !Event.MessageUpdate {
    const message = try self.messages.cache.patch(
        self,
        try .resolve(data.inner_message.id),
        .{
            .base = data.inner_message,
            .guild_id = switch (data.extra.guild_id) {
                .not_given => null,
                .val => |guild_id| guild_id,
            },
            .member = switch (data.extra.member) {
                .not_given => null,
                .val => |member| member,
            },
            .mentions = data.extra.mentions,
        },
    );
    try self.messages.pool.add(message);

    return .{ .arena = arena, .message = message };
}

fn processInteractionCreate(
    self: *Client,
    arena: std.mem.Allocator,
    data: gateway_message.payload.InteractionCreate,
) !Event.InteractionCreate {
    var interaction: Interaction = .{
        .context = self,
        .id = try .resolve(data.id),
    };

    try interaction.patch(data);

    return .{
        .arena = arena,
        .interaction = interaction,
        .token = data.token,
    };
}

fn DispatchPayloadType(dispatch_type: DispatchType) type {
    return switch (dispatch_type) {
        .ready => gateway_message.payload.Ready,
        .user_update => gateway_message.payload.UserUpdate,
        .guild_create => gateway_message.payload.GuildCreate,
        .guild_member_add => gateway_message.payload.GuildMemberAdd,
        .guild_member_remove => gateway_message.payload.GuildMemberRemove,
        .guild_member_update => gateway_message.payload.GuildMemberUpdate,
        .message_create => gateway_message.payload.MessageCreate,
        .message_delete => gateway_message.payload.MessageDelete,
        .message_update => gateway_message.payload.MessageUpdate,
        .interaction_create => gateway_message.payload.InteractionCreate,
    };
}

fn dispatchProcessFunctionName(dispatch_type: DispatchType) []const u8 {
    return switch (dispatch_type) {
        .ready => "processReadyEvent",
        .user_update => "processUserUpdate",
        .guild_create => "processGuildCreate",
        .guild_member_add => "processGuildMemberAdd",
        .guild_member_remove => "processGuildMemberRemove",
        .guild_member_update => "processGuildMemberUpdate",
        .message_create => "processMessageCreate",
        .message_delete => "processMessageDelete",
        .message_update => "processMessageUpdate",
        .interaction_create => "processInteractionCreate",
    };
}

pub fn processGatewayMessage(self: *Client, allocator: std.mem.Allocator, message: gateway.MessageRead) !?Event {
    switch (message) {
        .dispatch_event => |dispatch_event| {
            log.info("Got event {s}", .{dispatch_event.name});

            const dispatch_event_type = Event.dispatch_id_map.get(dispatch_event.name) orelse return null;

            switch (dispatch_event_type) {
                inline else => |tag| {
                    const data = try std.json.parseFromValueLeaky(
                        DispatchPayloadType(tag),
                        allocator,
                        dispatch_event.data_json,
                        .{ .allocate = .alloc_always, .ignore_unknown_fields = true },
                    );

                    const dispatch_fn = @field(Client, dispatchProcessFunctionName(tag));

                    return @unionInit(Event, @tagName(tag), try dispatch_fn(self, allocator, data));
                },
            }
        },
        .reconnect => {
            log.info("Server requested reconnect", .{});
            // self.maybe_reconnect_options = try self.maybe_gateway_client.?.options.dupe(self.allocator);
            try self.disconnect();
        },
        .hello, .invalid_session => {
            // TODO: handle
        },
        .close => |maybe_close_opcode| {
            if (maybe_close_opcode) |close_opcode| {
                log.info("Got close {}, can reconnect? {}", .{ close_opcode, close_opcode.reconnect() });

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
                log.info("Got unexpected close without a reason", .{});
                // self.clearReconnect(); // let's try to reconnect if the socket closes 'normally'
                return error.UnexpectedClose;
            }
        },
    }
    return null;
}

pub fn receive(self: *Client, arena: *std.heap.ArenaAllocator) !Event {
    const gateway_client: *StandardGatewayClient = &(self.maybe_gateway_client orelse return error.NotConnected);

    while (true) {
        _ = arena.reset(.retain_capacity);

        const allocator = arena.allocator();

        const message = gateway_client.readMessage(allocator) catch |e| switch (e) {
            error.TlsConnectionTruncated => {
                gateway_client.deinit();
                self.maybe_gateway_client = null;
                return error.Disconnected;
            },
            else => return e,
        };

        if (try self.processGatewayMessage(arena.allocator(), message)) |event| {
            return event;
        }
    }
}

pub fn receiveAndDispatch(self: *Client, handler: anytype) !void {
    var arena: std.heap.ArenaAllocator = .init(self.allocator);
    defer arena.deinit();

    const event = try self.receive(&arena);
    try Event.dispatch(event, handler);
}

pub const MessageWriter = struct {
    pub const Options = struct {
        pub const Reference = union(enum(i32)) {
            reply_to: Snowflake,
            forward: struct {
                message_id: Snowflake,
                channel_id: Snowflake,
                guild_id: Snowflake,
            },

            pub fn jsonStringify(self: Reference, jw: anytype) !void {
                try jw.beginObject();
                {
                    try jw.objectField("type");
                    try jw.write(@intFromEnum(std.meta.activeTag(self)));
                }
                switch (self) {
                    .reply_to => |message_id| {
                        try jw.objectField("message_id");
                        try jw.write(message_id);
                    },
                    .forward => |forward_options| {
                        {
                            try jw.objectField("message_id");
                            try jw.write(forward_options.message_id);
                        }
                        {
                            try jw.objectField("channel_id");
                            try jw.write(forward_options.channel_id);
                        }
                        {
                            try jw.objectField("guild_id");
                            try jw.write(forward_options.guild_id);
                        }
                    },
                }
                try jw.endObject();
            }
        };

        reference: ?Reference = null,
    };

    client: *Client,
    options: Options,

    req: Rest.Request,
    form_writer: Rest.Request.FormDataWriter,

    added_message_data: bool = false,
    num_files: usize = 0,

    pub fn deinit(self: *MessageWriter) void {
        self.req.deinit();
    }

    fn assertNoMessageData(self: *MessageWriter) void {
        std.debug.assert(!self.added_message_data);
        self.added_message_data = true;
    }

    pub fn write(self: *MessageWriter, message_builder: MessageBuilder) !void {
        self.assertNoMessageData();
        try self.form_writer.beginTextEntry("payload_json");

        {
            var new_writer = self.form_writer.writer().adaptToNewApi();

            var json_writer: std.json.Stringify = .{ .writer = &new_writer.new_interface };
            try json_writer.beginObject();

            try message_builder.jsonStringifyInner(&json_writer);
            if (self.options.reference) |reference| {
                try json_writer.objectField("message_reference");
                try json_writer.write(reference);
            }
            try json_writer.endObject();

            try new_writer.new_interface.flush();
        }

        try self.form_writer.endEntry();
    }

    pub fn writer(self: *MessageWriter) Rest.Request.HttpWriter {
        return self.form_writer.writer();
    }

    pub fn beginContent(self: *MessageWriter) !void {
        self.assertNoMessageData();
        try self.form_writer.beginTextEntry("content");
    }

    pub fn beginAttachment(self: *MessageWriter, file_type: []const u8, file_name: []const u8) !void {
        defer self.num_files += 1;

        try self.form_writer.beginFileEntryFmt("files[{d}]", .{self.num_files}, file_type, file_name);
    }

    pub fn writeAttachment(self: *MessageWriter, file_type: []const u8, file_name: []const u8, file_data: []const u8) !void {
        try self.beginAttachment(file_type, file_name);
        try self.writer().writeAll(file_data);
        try self.end();
    }

    pub fn end(self: *MessageWriter) !void {
        try self.form_writer.endEntry();
    }

    pub fn create(self: *MessageWriter) !*Message {
        try self.form_writer.endEntries();
        const message_response = try self.req.fetchJson(gateway_message.Message);
        return try self.client.messages.cache.patch(self.client, try .resolve(message_response.id), .{
            .base = message_response,
            .guild_id = null,
            .member = null,
            .mentions = &.{},
        });
    }
};

pub fn messageWriter(self: *Client, channel_id: Snowflake, options: MessageWriter.Options) !MessageWriter {
    var req = try self.rest_client.create(.POST, endpoints.create_message, .{
        .channel_id = channel_id,
    });
    errdefer req.deinit();

    var writer = req.writer();
    const form_writer = try writer.formDataWriter();

    return .{
        .client = self,
        .options = options,
        .req = req,
        .form_writer = form_writer,
    };
}

pub fn createMessage(
    self: *Client,
    channel_id: Snowflake,
    message_builder: MessageBuilder,
    options: MessageWriter.Options,
) !*Message {
    defer message_builder.deinit();
    var writer = try self.messageWriter(channel_id, options);
    defer writer.deinit();
    try writer.write(message_builder);
    return try writer.createMessage();
}

pub fn deleteMessage(self: *Client, channel_id: Snowflake, message_id: Snowflake) !void {
    var req = try self.rest_client.create(.DELETE, endpoints.delete_message, .{
        .channel_id = channel_id,
        .message_id = message_id,
    });
    defer req.deinit();
    try req.fetch();
}

pub fn createDM(self: *Client, user_id: Snowflake) !*Channel {
    var req = try self.rest_client.create(.POST, endpoints.create_dm, .{});
    errdefer req.deinit();

    var writer = req.writer();
    var jw = try writer.jsonWriter();

    try jw.beginObject();
    {
        try jw.objectField("recipient_id");
        try jw.write(user_id);
    }
    try jw.endObject();

    const channel_response = try req.fetchJson(gateway_message.Channel);
    const channel = try self.channels.cache.patch(self, try .resolve(channel_response.id), channel_response);
    try self.channels.pool.add(channel);
    return channel;
}

pub fn deleteChannel(self: *Client, channel_id: Snowflake) !void {
    var req = try self.rest_client.create(.DELETE, endpoints.delete_channel, .{
        .channel_id = channel_id,
    });
    defer req.deinit();
    try req.fetch();
}

pub fn triggerTypingIndicator(self: *Client, channel_id: Snowflake) !void {
    var req = try self.rest_client.create(.POST, endpoints.trigger_typing_indicator, .{
        .channel_id = channel_id,
    });
    defer req.deinit();
    try req.fetch();
}

pub const ReactionAdd = union(enum) {
    unicode: []const u8,
    custom: struct {
        name: []const u8,
        id: Snowflake,
    },

    pub fn format(self: ReactionAdd, writer: *std.io.Writer) !void {
        switch (self) {
            .unicode => |str| try writer.print("{%}", .{@as(std.Uri.Component, .{ .raw = str })}),
            .custom => |custom_emoji| try writer.print("{s}:{f}", .{ custom_emoji.name, custom_emoji.id }),
        }
    }
};

pub fn createReaction(
    self: *Client,
    channel_id: Snowflake,
    message_id: Snowflake,
    reaction: ReactionAdd,
) !void {
    var req = try self.rest_client.create(.PUT, endpoints.create_reaction, .{
        .channel_id = channel_id,
        .message_id = message_id,
        .emoji_id = reaction,
    });
    defer req.deinit();
    try req.fetch();
}

pub const StartThreadOptions = struct {
    pub const Type = union(enum) {
        public,
        private: struct {
            invitable: bool,
        },
        announcement,

        pub fn channelType(self: Type) Channel.Type {
            return switch (self) {
                .public => .public_thread,
                .private => .private_thread,
                .announcement => .announcement_thread,
            };
        }
    };

    pub const ArchiveDuration = enum(i32) {
        @"1h" = 60,
        @"1d" = 1440,
        @"3d" = 4320,
        @"1w" = 10080,
    };

    auto_archive_after: ?ArchiveDuration = null,
    rate_limit_seconds: ?u32 = null,

    // not jsonStringify because it doesn't create an object
    // to be stringified as a value in itself
    fn jsonStringifyInner(options: StartThreadOptions, jw: anytype) !void {
        if (options.auto_archive_after) |auto_archive_after| {
            try jw.objectField("auto_archive_duration");
            try jw.write(@intFromEnum(auto_archive_after));
        }
        if (options.rate_limit_seconds) |rate_limit| {
            try jw.objectField("rate_limit_per_user");
            try jw.write(rate_limit);
        }
    }
};

pub fn startThreadWithoutMessage(
    self: *Client,
    channel_id: Snowflake,
    @"type": StartThreadOptions.Type,
    name: []const u8,
    options: StartThreadOptions,
) !*Channel {
    var req = try self.rest_client.create(.POST, endpoints.start_thread_without_message, .{
        .channel_id = channel_id,
    });
    errdefer req.deinit();

    var writer = req.writer();
    var jw = try writer.jsonWriter();

    try jw.beginObject();
    {
        try jw.objectField("name");
        try jw.write(name);
    }
    {
        try jw.objectField("type");
        try jw.write(@intFromEnum(@"type".channelType()));
    }
    switch (@"type") {
        .public, .announcement => {},
        .private => |private_options| {
            try jw.objectField("invitable");
            try jw.write(private_options.invitable);
        },
    }

    try options.jsonStringifyInner(&jw);
    try jw.endObject();

    const channel_response = try req.fetchJson(gateway_message.Channel);
    const channel = try self.channels.cache.patch(self, try .resolve(channel_response.id), channel_response);
    try self.channels.pool.add(channel);
    return channel;
}

pub fn startThreadFromMessage(
    self: *Client,
    channel_id: Snowflake,
    message_id: Snowflake,
    name: []const u8,
    options: StartThreadOptions,
) !*Channel {
    var req = try self.rest_client.create(.POST, endpoints.start_thread_from_message, .{
        .channel_id = channel_id,
        .message_id = message_id,
    });
    errdefer req.deinit();

    var writer = req.writer();
    var jw = try writer.jsonWriter();

    try jw.beginObject();
    {
        try jw.objectField("name");
        try jw.write(name);
    }
    try options.jsonStringifyInner(&jw);
    try jw.endObject();

    const channel_response = try req.fetchJson(gateway_message.Channel);
    const channel = try self.channels.cache.patch(self, try .resolve(channel_response.id), channel_response);
    try self.channels.pool.add(channel);
    return channel;
}

pub fn bulkOverwriteGlobalApplicationCommands(
    self: *Client,
    application_id: Snowflake,
    application_command_builders: []const ApplicationCommandBuilder,
) !void {
    var req = try self.rest_client.create(.PUT, endpoints.bulk_overwrite_global_application_commands, .{
        .application_id = application_id,
    });
    defer req.deinit();

    var writer = req.writer();
    var jw = try writer.jsonWriter();

    try jw.beginArray();
    {
        for (application_command_builders) |builder| {
            try jw.write(builder);
        }
    }
    try jw.endArray();

    const application_commands_response = try req.fetchJson(std.json.Value);
    _ = application_commands_response;
}

pub const ResponseWriter = struct {
    client: *Client,

    req: Rest.Request,
    form_writer: Rest.Request.FormDataWriter,
    type: Interaction.ResponseType,

    added_message_data: bool = false,
    num_files: usize = 0,

    pub fn deinit(self: *ResponseWriter) void {
        self.req.deinit();
    }

    fn assertNoMessageData(self: *ResponseWriter) void {
        std.debug.assert(!self.added_message_data);
        self.added_message_data = true;
    }

    pub fn write(self: *ResponseWriter, message_builder: MessageBuilder) !void {
        self.assertNoMessageData();
        try self.form_writer.beginTextEntry("payload_json");

        {
            var new_writer = self.form_writer.writer().adaptToNewApi();

            var json_writer: std.json.Stringify = .{ .writer = &new_writer.new_interface };
            try json_writer.beginObject();

            {
                try json_writer.objectField("type");
                try json_writer.write(@intFromEnum(self.type));

                try json_writer.objectField("data");
                try json_writer.write(message_builder);
            }

            try json_writer.endObject();

            try new_writer.new_interface.flush();
        }

        try self.form_writer.endEntry();
    }

    pub fn writer(self: *ResponseWriter) Rest.Request.HttpWriter {
        return self.form_writer.writer();
    }

    pub fn beginAttachment(self: *ResponseWriter, file_type: []const u8, file_name: []const u8) !void {
        defer self.num_files += 1;

        try self.form_writer.beginFileEntryFmt("data.files[{d}]", .{self.num_files}, file_type, file_name);
    }

    pub fn writeAttachment(self: *ResponseWriter, file_type: []const u8, file_name: []const u8, file_data: []const u8) !void {
        try self.beginAttachment(file_type, file_name);
        try self.writer().writeAll(file_data);
        try self.end();
    }

    pub fn end(self: *ResponseWriter) !void {
        try self.form_writer.endEntry();
    }

    pub fn create(self: *ResponseWriter) !void {
        try self.form_writer.endEntries();
        _ = try self.req.fetchJson(std.json.Value);
    }
};

pub fn interactionResponseMessageWriter(
    self: *Client,
    interaction_id: Snowflake,
    interaction_token: []const u8,
) !ResponseWriter {
    var req = try self.rest_client.create(.POST, endpoints.create_interaction_response ++ "?with_response=true", .{
        .interaction_id = interaction_id,
        .interaction_token = interaction_token,
    });
    errdefer req.deinit();

    var writer = req.writer();
    const form_writer = try writer.formDataWriter();

    return .{
        .client = self,
        .type = .channel_message_with_source,
        .req = req,
        .form_writer = form_writer,
    };
}

pub fn createInteractionResponseMessage(
    self: *Client,
    interaction_id: Snowflake,
    interaction_token: []const u8,
    message_builder: MessageBuilder,
) !void {
    defer message_builder.deinit();
    var writer = try self.interactionResponseMessageWriter(interaction_id, interaction_token);
    defer writer.deinit();
    try writer.write(message_builder);
    try writer.create();
}
