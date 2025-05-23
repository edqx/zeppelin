const std = @import("std");

const Snowflake = @import("../snowflake.zig").Snowflake;
const QueriedFields = @import("../queryable.zig").QueriedFields;
const Client = @import("../Client.zig");

const Permissions = @import("../permissions.zig").Permissions;

const Cache = @import("../cache.zig").Cache;
const Pool = @import("../cache.zig").Pool;

const Channel = @import("Channel.zig");
const Role = @import("Role.zig");
const User = @import("User.zig");

const gateway_message = @import("../gateway_message.zig");

pub const Data = union(enum) {
    unavailable: gateway_message.Guild.Unavailable,
    available: struct {
        base: gateway_message.Guild,
        channels: ?[]gateway_message.Channel,
        members: ?[]gateway_message.Guild.Member,
    },
};

pub const Member = struct {
    pub const Data = @import("../gateway_message.zig").Guild.Member;

    pub const Flags = packed struct(i32) {
        did_rejoin: bool,
        completed_onboarding: bool,
        bypasses_verification: bool,
        started_onboarding: bool,
        is_guest: bool,
        started_home_actions: bool,
        completed_home_actions: bool,
        automod_quarantined_username: bool,
        _packed1: enum(u1) { unset } = .unset,
        dm_settings_upsell_acknowledged: bool,
    };

    meta: QueriedFields(Member, &.{
        "user", "nick", "roles",
    }) = .none,

    context: *Guild,
    id: Snowflake,

    guild: *Guild = undefined,

    user: *User = undefined,
    nick: ?[]const u8 = null,
    roles: Pool(Role) = undefined,

    pub fn init(self: *Member) void {
        self.guild = self.context;
        const allocator = self.guild.context.allocator;

        self.roles = .{ .allocator = allocator };
    }

    pub fn deinit(self: *Member) void {
        const allocator = self.guild.context.allocator;

        self.roles.deinit();
        if (self.nick) |nick| allocator.free(nick);
    }

    pub fn patch(self: *Member, data: Member.Data) !void {
        const allocator = self.guild.context.allocator;

        const users_cache = &self.guild.context.global_cache.users;
        const roles_cache = &self.guild.context.global_cache.roles;

        switch (data.user) {
            .not_given => {},
            .val => |data_user| {
                const user = try users_cache.patch(self.guild.context, try .resolve(data_user.id), data_user);
                self.meta.patch(.user, user);
            },
        }

        switch (data.nick) {
            .not_given => {},
            .val => |maybe_nick| {
                if (self.nick) |nick| allocator.free(nick);
                self.meta.patch(.nick, if (maybe_nick) |data_nick| try allocator.dupe(u8, data_nick) else null);
            },
        }

        self.roles.clear();

        const everyone_role = try self.guild.everyoneRole();
        try self.roles.add(everyone_role);

        for (data.roles) |role_id| {
            const role = try roles_cache.touch(self.guild.context, try .resolve(role_id));
            role.meta.patch(.guild, self.guild);
            try self.roles.add(role);
        }
    }

    pub fn owner(self: *Member) bool {
        return self.id == self.guild.owner_id;
    }

    pub fn computePermissions(self: *Member) Permissions {
        if (self.owner()) return .all;

        var final: Permissions = .{};

        for (self.roles) |role| {
            final = final.withAllowed(role.permissions);
        }

        return if (final.administrator) .all else final;
    }
};

const Guild = @This();

meta: QueriedFields(Guild, &.{
    "available", "name",  "owner_id",
    "channels",  "roles",
}) = .none,

context: *Client,
id: Snowflake,

available: bool = false,

name: []const u8 = "",
owner_id: Snowflake = undefined,
channels: Pool(Channel) = undefined,
roles: Pool(Role) = undefined,

members: Cache(Member, *Guild) = undefined,

pub fn init(self: *Guild) void {
    const allocator = self.context.allocator;
    self.members = .init(allocator);
    self.channels = .{ .allocator = allocator };
    self.roles = .{ .allocator = allocator };
}

pub fn deinit(self: *Guild) void {
    const allocator = self.context.allocator;

    self.members.deinit();

    self.roles.deinit();
    self.channels.deinit();
    allocator.free(self.name);
}

fn patchAvailable(self: *Guild, inner_data: @FieldType(Data, "available")) !void {
    const allocator = self.context.allocator;

    const channels_cache = &self.context.global_cache.channels;
    const roles_cache = &self.context.global_cache.roles;

    allocator.free(self.name);
    self.meta.patch(.name, try allocator.dupe(u8, inner_data.base.name));

    self.meta.patch(.owner_id, try .resolve(inner_data.base.owner_id));

    if (inner_data.channels) |channels_data| {
        self.channels.clear();

        for (channels_data) |channel_data| {
            var modified_data = channel_data;
            modified_data.guild_id = .{ .val = inner_data.base.id }; // work-around, because guild.channels don't have the guild id with them

            const channel = try channels_cache.patch(self.context, try .resolve(modified_data.id), modified_data);
            try self.channels.add(channel);
        }
    }

    if (inner_data.members) |members_data| {
        for (members_data) |member_data| {
            switch (member_data.user) {
                .not_given => {}, // there's not really much we can do without a user id
                .val => |data_user| {
                    _ = try self.members.patch(self, try .resolve(data_user.id), member_data);
                },
            }
        }
    }

    self.roles.clear();

    const everyone_role = try self.everyoneRole();
    try self.roles.add(everyone_role);

    for (inner_data.base.roles) |role_data| {
        const role = try roles_cache.patch(self.context, try .resolve(role_data.id), role_data);
        role.meta.patch(.guild, self);
        try self.roles.add(role);
    }
}

pub fn patch(self: *Guild, data: Data) !void {
    self.meta.patch(.available, data == .available);

    switch (data) {
        .available => |inner_data| try self.patchAvailable(inner_data),
        .unavailable => {
            self.meta = .none;
            self.available = false;
        },
    }
}

pub fn everyoneRole(self: *Guild) !*Role {
    const roles_cache = &self.context.global_cache.roles;

    const everyone_role = try roles_cache.touch(self.context, self.id);
    everyone_role.meta.patch(.guild, self);
    return everyone_role;
}
