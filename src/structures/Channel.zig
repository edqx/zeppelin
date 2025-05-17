const std = @import("std");

const Snowflake = @import("../snowflake.zig").Snowflake;
const QueriedFields = @import("../queryable.zig").QueriedFields;
const Client = @import("../Client.zig");

const Permissions = @import("../permissions.zig").Permissions;

const gateway_message = @import("../gateway_message.zig");

const Guild = @import("Guild.zig");
const Message = @import("Message.zig");
const User = @import("User.zig");

pub const Data = @import("../gateway_message.zig").Channel;

const Channel = @This();

pub const Type = enum(i32) {
    unknown = -1,
    guild_text = 0,
    dm,
    guild_voice,
    group_dm,
    guild_category,
    guild_announcement,
    announcement_thread = 10,
    public_thread,
    private_thread,
    guild_stage_voice,
    guild_directory,
    guild_forum,
    guild_media,

    pub fn messageable(self: Type) bool {
        return switch (self) {
            .unknown => unreachable,
            .guild_text,
            .dm,
            .guild_voice,
            .group_dm,
            .guild_announcement,
            .announcement_thread,
            .public_thread,
            .private_thread,
            .guild_stage_voice,
            .guild_forum,
            .guild_media,
            => true,
            .guild_category, .guild_directory => false,
        };
    }
};

pub const PermissionOverwrite = struct {};

pub fn AnyChannel(comptime channel_type: Type, comptime used_fields: []const [:0]const u8) type {
    return struct {
        inline fn hasField(field: []const u8) bool {
            return comptime for (used_fields) |used_field| {
                if (std.mem.eql(u8, used_field, field)) break true;
            } else false;
        }

        const AnyChannelT = @This();

        context: *Client,

        meta: QueriedFields(AnyChannelT, used_fields) = .none,

        id: Snowflake,
        guild: if (hasField("guild")) *Guild else void = if (hasField("guild")) undefined else {},
        name: if (hasField("name")) ?[]const u8 else void = if (hasField("name")) null else {},

        permission_overwrites: if (hasField("permission_overwrites")) []Permissions.Overwrite else void = if (hasField("permission_overwrites")) &.{} else {},

        pub fn deinit(self: *AnyChannelT) void {
            const allocator = self.context.allocator;

            if (hasField("name")) if (self.name) |name| allocator.free(name);
            if (hasField("permission_overwrites")) allocator.free(self.permission_overwrites);
        }

        pub fn patch(self: *AnyChannelT, data: Data) !void {
            const allocator = self.context.allocator;

            if (hasField("guild")) {
                switch (data.guild_id) {
                    .not_given => {},
                    .val => |guild_id| self.meta.patch(
                        .guild,
                        try self.context.global_cache.guilds.touch(self.context, try .resolve(guild_id)),
                    ),
                }
            }

            if (hasField("name")) {
                switch (data.name) {
                    .not_given => {},
                    .val => |maybe_name| {
                        if (self.name) |name| allocator.free(name);
                        self.meta.patch(.name, if (maybe_name) |data_name| try allocator.dupe(u8, data_name) else null);
                    },
                }
            }

            if (hasField("permission_overwrites")) {
                switch (data.permission_overwrites) {
                    .not_given => {},
                    .val => |data_permission_overwrites| {
                        var permission_overwrites: std.ArrayListUnmanaged(Permissions.Overwrite) = try .initCapacity(allocator, data_permission_overwrites.len);
                        defer permission_overwrites.deinit(allocator);

                        for (data_permission_overwrites) |overwrite_data| {
                            const overwrite: Permissions.Overwrite = try .parseFromGatewayData(overwrite_data);
                            permission_overwrites.appendAssumeCapacity(overwrite);
                        }

                        allocator.free(self.permission_overwrites);
                        self.meta.patch(.permission_overwrites, try permission_overwrites.toOwnedSlice(allocator));
                    },
                }
            }
        }

        pub fn createMessage(self: *AnyChannelT, content: []const u8) !*Message {
            comptime if (!channel_type.messageable()) @compileError("Cannot create messages in " ++ @tagName(channel_type) ++ " channels");
            return try self.context.createMessage(self.id, content);
        }

        pub fn roleOverwrite(self: *AnyChannelT, role_id: Snowflake) ?Permissions.Overwrite {
            return for (self.permission_overwrites) |overwrite| {
                if (overwrite.type == .role and overwrite.id == role_id) break overwrite;
            } else null;
        }

        pub fn memberOverwrite(self: *AnyChannelT, member_user_id: Snowflake) ?Permissions.Overwrite {
            return for (self.permission_overwrites) |overwrite| {
                if (overwrite.type == .member and overwrite.id == member_user_id) break overwrite;
            } else null;
        }

        pub fn computePermissionsForMember(self: *AnyChannelT, member: *Guild.Member) {
            var member_permissions = member.computePermissions();

            if (member_permissions.administrator) return .all;

            if (self.roleOverwrite(self.guild.id)) |overwrite| { // everyone
                member_permissions = member_permissions.withDenied(overwrite.deny).withAllowed(overwrite.allow);
            }

            var allow_permissions: Permissions = .{};
            var deny_permissions: Permissions = .{};
            for (self.permission_overwrites) |overwrite| {
                switch (overwrite.type) {
                    .member => {},
                    .role => {
                        const has_role = for (member.roles) |role| {
                            if (role.id == overwrite.id) break true;
                        } else false;
                        if (has_role) {
                            allow_permissions = allow_permissions.withAllowed(overwrite.allow);
                            deny_permissions = deny_permissions.withDenied(overwrite.deny);
                        }
                    },
                }
            }
            member_permissions = member_permissions.withDenied(deny_permissions).withAllowed(allow_permissions);

            const member_overwrite = for (self.permission_overwrites) |overwrite| {
                if (overwrite.type == .member and overwrite.id == member.id) break overwrite;
            } else null;
            if (member_overwrite) |overwrite| {
                member_permissions = member_permissions.withDenied(overwrite.deny).withAllowed(overwrite.allow);
            }
            return member_permissions;
        }
    };
}

pub const Inner = union(Type) {
    const in_guild: []const [:0]const u8 = &.{ "guild", "permission_overwrites" };
    const has_name: []const [:0]const u8 = &.{"name"};

    unknown: void,
    guild_text: AnyChannel(.guild_text, in_guild ++ has_name),
    dm: AnyChannel(.dm, &.{}),
    guild_voice: AnyChannel(.guild_voice, in_guild ++ has_name),
    group_dm: AnyChannel(.dm, has_name),
    guild_category: AnyChannel(.guild_category, in_guild ++ has_name),
    guild_announcement: AnyChannel(.guild_announcement, in_guild ++ has_name),
    announcement_thread: AnyChannel(.announcement_thread, in_guild ++ has_name),
    public_thread: AnyChannel(.public_thread, in_guild ++ has_name),
    private_thread: AnyChannel(.private_thread, in_guild ++ has_name),
    guild_stage_voice: AnyChannel(.guild_stage_voice, in_guild ++ has_name),
    guild_directory: AnyChannel(.guild_directory, in_guild ++ has_name),
    guild_forum: AnyChannel(.guild_forum, in_guild ++ has_name),
    guild_media: AnyChannel(.guild_media, in_guild ++ has_name),
};

meta: QueriedFields(Channel, &.{
    "inner",
}) = .none,

context: *Client,
id: Snowflake,

inner: Inner = .unknown,

pub fn deinit(self: *Channel) void {
    switch (self.inner) {
        .unknown => {},
        inline else => |*inner| inner.deinit(),
    }
}

pub fn patch(self: *Channel, data: Data) !void {
    const @"type" = @as(Type, @enumFromInt(data.type));
    var inner = switch (@"type") {
        .unknown => unreachable,
        inline else => |tag| @unionInit(Inner, @tagName(tag), .{
            .context = self.context,
            .id = self.id,
        }),
    };

    switch (inner) {
        .unknown => unreachable,
        inline else => |*any_channel| try any_channel.patch(data),
    }

    self.meta.patch(.inner, inner);
}
