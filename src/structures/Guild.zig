const std = @import("std");

const Snowflake = @import("../snowflake.zig").Snowflake;
const QueriedFields = @import("../queryable.zig").QueriedFields;
const Client = @import("../Client.zig");

const Permissions = @import("../permissions.zig").Permissions;

const Cache = @import("../cache.zig").Cache;

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
    roles: []*Role = &.{},

    pub fn init(self: *Member) void {
        self.guild = self.context;
    }

    pub fn deinit(self: *Member) void {
        const allocator = self.guild.context.allocator;

        allocator.free(self.roles);
        if (self.nick) |nick| allocator.free(nick);
    }

    pub fn patch(self: *Member, data: Member.Data) !void {
        const allocator = self.guild.context.allocator;

        switch (data.user) {
            .not_given => {},
            .val => |data_user| {
                const user = try self.guild.context.global_cache.users.patch(self.guild.context, try .resolve(data_user.id), data_user);
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

        var role_references: std.ArrayListUnmanaged(*Role) = try .initCapacity(allocator, 1 + data.roles.len);
        defer role_references.deinit(allocator);

        const everyone_role = try self.guild.context.global_cache.roles.touch(self.guild.context, self.guild.id);
        everyone_role.guild = self.guild;
        role_references.appendAssumeCapacity(everyone_role);

        for (data.roles) |role_id| {
            const role = try self.guild.context.global_cache.roles.touch(self.guild.context, try .resolve(role_id));
            role.guild = self.guild;
            role_references.appendAssumeCapacity(role);
        }

        allocator.free(self.roles);
        self.meta.patch(.roles, try role_references.toOwnedSlice(allocator));
    }

    pub fn computePermissions(self: *Member) Permissions {
        var final: Permissions = .{};

        for (self.roles) |role| {
            final = final.withAllowed(role.permissions);
        }

        return if (final.administrator) .all else final;
    }
};

const Guild = @This();

meta: QueriedFields(Guild, &.{
    "available", "name", "channels",
    "roles",
}) = .none,

context: *Client,
id: Snowflake,

available: bool = false,
name: []const u8 = "",
channels: []*Channel = &.{},
roles: []*Role = &.{},

members: Cache(Member, *Guild) = undefined,

pub fn init(self: *Guild) void {
    const allocator = self.context.allocator;
    self.members = .init(allocator);
}

pub fn deinit(self: *Guild) void {
    const allocator = self.context.allocator;

    self.members.deinit();

    allocator.free(self.roles);
    allocator.free(self.channels);
    allocator.free(self.name);
}

fn patchAvailable(self: *Guild, inner_data: @FieldType(Data, "available")) !void {
    const allocator = self.context.allocator;

    allocator.free(self.name);
    self.meta.patch(.name, try allocator.dupe(u8, inner_data.base.name));

    if (inner_data.channels) |channnels_data| {
        var channel_references: std.ArrayListUnmanaged(*Channel) = try .initCapacity(allocator, channnels_data.len);
        defer channel_references.deinit(allocator);

        for (channnels_data) |channel_data| {
            var modified_data = channel_data;
            modified_data.guild_id = .{ .val = inner_data.base.id }; // guild.channels don't have the guild id with them

            const channel = try self.context.global_cache.channels.patch(self.context, try .resolve(modified_data.id), modified_data);
            channel_references.appendAssumeCapacity(channel);
        }

        allocator.free(self.channels);
        self.meta.patch(.channels, try channel_references.toOwnedSlice(allocator));
    }

    if (inner_data.members) |members_data| {
        for (members_data) |member_data| {
            switch (member_data.user) {
                .not_given => {}, // there's not really much we can do without a user id
                .val => |data_user| {
                    const member = try self.members.touch(self, try .resolve(data_user.id));
                    try member.patch(member_data);
                },
            }
        }
    }

    var role_references: std.ArrayListUnmanaged(*Role) = try .initCapacity(allocator, inner_data.base.roles.len);
    defer role_references.deinit(allocator);

    for (inner_data.base.roles) |role_data| {
        const role = try self.context.global_cache.roles.patch(self.context, try .resolve(role_data.id), role_data);
        role_references.appendAssumeCapacity(role);
        role.guild = self;
    }

    allocator.free(self.roles);
    self.meta.patch(.roles, try role_references.toOwnedSlice(allocator));
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
