const std = @import("std");
const websocket = @import("websocket");
const wardrobe = @import("wardrobe");

const gateway = @import("gateway.zig");
const gateway_message = @import("gateway_message.zig");
const endpoints = @import("constants.zig").endpoints;

const Snowflake = @import("snowflake.zig").Snowflake;

const Authentication = @import("authentication.zig").Authentication;

const Cache = @import("cache.zig").Cache;
const Pool = @import("cache.zig").Pool;

const MessageBuilder = @import("MessageBuilder.zig");

const Rest = @import("Rest.zig");

const Channel = @import("structures/Channel.zig");
const Guild = @import("structures/Guild.zig");
const Message = @import("structures/Message.zig");
const Role = @import("structures/Role.zig");
const User = @import("structures/User.zig");

const Client = @This();

pub const DispatchType = enum {
    ready,
    guild_create,
    guild_member_add,
    guild_member_remove,
    message_create,
    message_delete,
};

pub const Event = union(DispatchType) {
    pub const Ready = struct {
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

    pub const MessageCreate = struct {
        arena: std.mem.Allocator,
        message: *Message,
    };

    pub const MessageDelete = struct {
        arena: std.mem.Allocator,
        message: *Message,
    };

    ready: Ready,
    guild_create: GuildCreate,
    guild_member_add: GuildMemberAdd,
    guild_member_remove: GuildMemberRemove,
    message_create: MessageCreate,
    message_delete: MessageDelete,
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

pub const dispatch_event_map: std.StaticStringMap(DispatchType) = .initComptime(.{
    .{ "READY", .ready },
    .{ "GUILD_CREATE", .guild_create },
    .{ "GUILD_MEMBER_ADD", .guild_member_add },
    .{ "GUILD_MEMBER_REMOVE", .guild_member_remove },
    .{ "MESSAGE_CREATE", .message_create },
    .{ "MESSAGE_DELETE", .message_delete },
});

pub const InitOptions = struct {
    allocator: std.mem.Allocator,
    authentication: Authentication,
};

allocator: std.mem.Allocator,
maybe_gateway_client: ?gateway.Client,
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

fn processReadyEvent(self: *Client, arena: std.mem.Allocator, json: std.json.Value) !Event.Ready {
    const ready_data = try std.json.parseFromValueLeaky(
        gateway_message.payload.Ready,
        arena,
        json,
        .{ .allocate = .alloc_always, .ignore_unknown_fields = true },
    );

    const user = try self.users.cache.patch(
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

    return .{ .arena = arena, .user = user };
}

fn processGuildCreate(self: *Client, arena: std.mem.Allocator, json: std.json.Value) !Event.GuildCreate {
    const guild_data = try std.json.parseFromValueLeaky(
        gateway_message.payload.GuildCreate,
        arena,
        json,
        .{ .allocate = .alloc_always, .ignore_unknown_fields = true },
    );

    const guild = switch (guild_data) {
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

fn processGuildMemberAdd(self: *Client, arena: std.mem.Allocator, json: std.json.Value) !Event.GuildMemberAdd {
    const users_cache = &self.users.cache;
    const guilds_cache = &self.guilds.cache;

    const guild_member_add_data = try std.json.parseFromValueLeaky(
        gateway_message.payload.GuildMemberAdd,
        arena,
        json,
        .{ .allocate = .alloc_always, .ignore_unknown_fields = true },
    );

    const guild_id = guild_member_add_data.extra.guild_id;
    const guild_member_data = guild_member_add_data.inner_guild_member;

    switch (guild_member_data.user) {
        .not_given => {
            return error.NoGuildUser;
        }, // what can we do with a guild member with no user?
        .val => |user_data| {
            const user = try users_cache.patch(self, try .resolve(user_data.id), user_data);
            const guild = try guilds_cache.touch(self, try .resolve(guild_id));
            const guild_member = try guild.members.cache.patch(guild, try .resolve(user.id), guild_member_data);
            try guild.members.pool.add(guild_member);

            return .{ .arena = arena, .guild = guild, .guild_member = guild_member };
        },
    }
    unreachable;
}

fn processGuildMemberRemove(self: *Client, arena: std.mem.Allocator, json: std.json.Value) !Event.GuildMemberRemove {
    const users_cache = &self.users.cache;
    const guilds_cache = &self.guilds.cache;

    const guild_member_remove_data = try std.json.parseFromValueLeaky(
        gateway_message.payload.GuildMemberRemove,
        arena,
        json,
        .{ .allocate = .alloc_always, .ignore_unknown_fields = true },
    );

    const user_data = guild_member_remove_data.user;

    const guild = try guilds_cache.touch(self, try .resolve(guild_member_remove_data.guild_id));

    const user = try users_cache.patch(self, try .resolve(user_data.id), user_data);
    const guild_member = try guild.members.cache.touch(guild, try .resolve(user_data.id));
    guild.members.pool.remove(try .resolve(user_data.id));
    guild_member.meta.patch(.user, user);

    return .{ .arena = arena, .guild = guild, .guild_member = guild_member };
}

fn processMessageCreate(self: *Client, arena: std.mem.Allocator, json: std.json.Value) !Event.MessageCreate {
    const message_data = try std.json.parseFromValueLeaky(
        gateway_message.payload.MessageCreate,
        arena,
        json,
        .{ .allocate = .alloc_always, .ignore_unknown_fields = true },
    );

    const message = try self.messages.cache.patch(
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

    return .{ .arena = arena, .message = message };
}

fn processMessageDelete(self: *Client, arena: std.mem.Allocator, json: std.json.Value) !Event.MessageDelete {
    const delete_data = try std.json.parseFromValueLeaky(
        gateway_message.payload.MessageDelete,
        arena,
        json,
        .{ .allocate = .alloc_always, .ignore_unknown_fields = true },
    );

    const message = try self.messages.cache.touch(self, try .resolve(delete_data.id));
    const channel = try self.channels.cache.touch(self, try .resolve(delete_data.channel_id));

    message.meta.patch(.channel, channel);
    switch (delete_data.guild_id) {
        .not_given => {},
        .val => |guild_id| message.meta.patch(.guild, try self.guilds.cache.touch(self, try .resolve(guild_id))),
    }
    self.messages.pool.remove(try .resolve(delete_data.id));

    return .{ .arena = arena, .message = message };
}

pub fn receive(self: *Client, arena: *std.heap.ArenaAllocator) !Event {
    const gateway_client: *gateway.Client = &(self.maybe_gateway_client orelse return error.NotConnected);

    while (true) {
        _ = arena.reset(.retain_capacity);

        const allocator = arena.allocator();

        switch (try gateway_client.readMessage(allocator)) {
            .dispatch_event => |dispatch_event| {
                const dispatch_event_type = dispatch_event_map.get(dispatch_event.name) orelse continue;

                switch (dispatch_event_type) {
                    .ready => return .{ .ready = try self.processReadyEvent(allocator, dispatch_event.data_json) },
                    .guild_create => return .{ .guild_create = try self.processGuildCreate(allocator, dispatch_event.data_json) },
                    .guild_member_add => return .{ .guild_member_add = try self.processGuildMemberAdd(allocator, dispatch_event.data_json) },
                    .guild_member_remove => return .{ .guild_member_remove = try self.processGuildMemberRemove(allocator, dispatch_event.data_json) },
                    .message_create => return .{ .message_create = try self.processMessageCreate(allocator, dispatch_event.data_json) },
                    .message_delete => return .{ .message_delete = try self.processMessageDelete(allocator, dispatch_event.data_json) },
                }
            },
            .reconnect => {
                const reconnect_options = self.maybe_gateway_client.?.options;
                try self.disconnect();
                try self.connectAndLogin(reconnect_options);
            },
            .hello, .invalid_session => {
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
                    // self.clearReconnect(); // let's try to reconnect if the socket closes 'normally'
                    return error.UnexpectedClose;
                }
            },
        }
    }
}

pub fn receiveAndDispatch(self: *Client, handler: anytype) !void {
    var arena: std.heap.ArenaAllocator = .init(self.allocator);
    defer arena.deinit();

    const event = try self.receive(&arena);

    switch (event) {
        .ready => |ev| if (@hasDecl(@TypeOf(handler.*), "ready")) try handler.ready(ev),
        .guild_create => |ev| if (@hasDecl(@TypeOf(handler.*), "guildCreate")) try handler.guildCreate(ev),
        .guild_member_add => |ev| if (@hasDecl(@TypeOf(handler.*), "guildMemberAdd")) try handler.guildMemberAdd(ev),
        .guild_member_remove => |ev| if (@hasDecl(@TypeOf(handler.*), "guildMemberRemove")) try handler.guildMemberRemove(ev),
        .message_create => |ev| if (@hasDecl(@TypeOf(handler.*), "messageCreate")) try handler.messageCreate(ev),
        .message_delete => |ev| if (@hasDecl(@TypeOf(handler.*), "messageDelete")) try handler.messageDelete(ev),
    }
}

pub const MessageWriter = struct {
    client: *Client,

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
            var json_writer = std.json.writeStream(self.form_writer.writer(), .{});
            try json_writer.write(message_builder);
        }

        try self.form_writer.endEntry();
    }

    pub fn writer(self: *MessageWriter) Rest.Request.Writer {
        return self.form_writer.writer();
    }

    pub fn beginContent(self: *MessageWriter) !void {
        self.assertNoMessageData();
        try self.form_writer.beginTextEntry("content");
    }

    pub fn beginAttachment(self: *MessageWriter, file_type: []const u8, file_name: []const u8) !void {
        defer self.num_files += 1;

        var buf: [16]u8 = undefined;
        const entry_name = try std.fmt.bufPrint(&buf, "files[{d}]", .{self.num_files});

        try self.form_writer.beginFileEntry(entry_name, file_type, file_name);
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

pub fn messageWriter(self: *Client, channel_id: Snowflake) !MessageWriter {
    var req = try self.rest_client.create(.POST, endpoints.create_message, .{
        .channel_id = channel_id,
    });
    errdefer req.deinit();

    const form_writer = try req.beginFormData();

    return .{
        .client = self,
        .req = req,
        .form_writer = form_writer,
    };
}

pub fn createMessage(self: *Client, channel_id: Snowflake, message_builder: MessageBuilder) !*Message {
    defer message_builder.deinit();
    var writer = try self.messageWriter(channel_id);
    try writer.write(message_builder);
    return try writer.create();
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

    var jw = try req.beginJson();

    try jw.beginObject();
    {
        try jw.objectField("recipient_id");
        try jw.write(user_id);
    }
    try jw.endObject();

    const channel_response = try req.fetchJson(gateway_message.Channel);
    const channel = try self.channels.cache.patch(self, try .resolve(channel_response.id), channel_response);
    try self.channels.add(channel);
    return channel;
}

pub fn deleteChannel(self: *Client, channel_id: Snowflake) !void {
    var req = try self.rest_client.create(.DELETE, endpoints.delete_channel, .{
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

    pub fn format(self: ReactionAdd, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self) {
            .unicode => |str| try writer.print("{%}", .{@as(std.Uri.Component, .{ .raw = str })}),
            .custom => |custom_emoji| try writer.print("{s}:{}", .{ custom_emoji.name, custom_emoji.id }),
        }
    }
};

pub fn createReaction(self: *Client, channel_id: Snowflake, message_id: Snowflake, reaction: ReactionAdd) !void {
    var req = try self.rest_client.create(.PUT, endpoints.create_reaction, .{
        .channel_id = channel_id,
        .message_id = message_id,
        .emoji_id = reaction,
    });
    defer req.deinit();
    try req.fetch();
}
