const std = @import("std");

const Snowflake = @import("../snowflake.zig").Snowflake;
const QueriedFields = @import("../queryable.zig").QueriedFields;
const Client = @import("../Client.zig");

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
};

pub const PermissionOverwrite = struct {};

pub fn AnyChannel(comptime used_fields: []const [:0]const u8) type {
    return struct {
        inline fn hasField(field: []const u8) bool {
            return comptime for (used_fields) |used_field| {
                if (std.mem.eql(u8, used_field, field)) break true;
            } else false;
        }

        const AnyChannelT = @This();

        context: *Client,

        meta: QueriedFields(AnyChannelT, used_fields) = .none,

        guild: if (hasField("guild")) *Guild else void = if (hasField("guild")) undefined else {},
        name: if (hasField("name")) ?[]const u8 else void = if (hasField("name")) null else {},

        pub fn deinit(self: *AnyChannelT) void {
            const allocator = self.context.allocator;

            if (hasField("name")) if (self.name) |name| allocator.free(name);
        }

        pub fn patch(self: *AnyChannelT, data: Data) !void {
            const allocator = self.context.allocator;

            if (hasField("guild")) {
                switch (data.guild_id) {
                    .not_given => {},
                    .val => |guild_id| self.meta.patch(.guild, try self.context.global_cache.guilds.touch(self.context, try .resolve(guild_id))),
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
        }
    };
}

pub const Inner = union(Type) {
    unknown: void,
    guild_text: AnyChannel(&.{ "guild", "name" }),
    dm: AnyChannel(&.{}),
    guild_voice: AnyChannel(&.{ "guild", "name" }),
    group_dm: AnyChannel(&.{"name"}),
    guild_category: AnyChannel(&.{ "guild", "name" }),
    guild_announcement: AnyChannel(&.{ "guild", "name" }),
    announcement_thread: AnyChannel(&.{ "guild", "name" }),
    public_thread: AnyChannel(&.{ "guild", "name" }),
    private_thread: AnyChannel(&.{ "guild", "name" }),
    guild_stage_voice: AnyChannel(&.{ "guild", "name" }),
    guild_directory: AnyChannel(&.{ "guild", "name" }),
    guild_forum: AnyChannel(&.{ "guild", "name" }),
    guild_media: AnyChannel(&.{ "guild", "name" }),
};

meta: QueriedFields(Channel, &.{
    "inner",
}) = .none,

context: *Client,
id: Snowflake,

inner: Inner = .unknown,

pub fn deinit(self: *Channel) void {
    _ = self;
}

pub fn patch(self: *Channel, data: Data) !void {
    const @"type" = @as(Type, @enumFromInt(data.type));
    var inner = switch (@"type") {
        .unknown => unreachable,
        inline else => |tag| @unionInit(Inner, @tagName(tag), .{
            .context = self.context,
        }),
    };

    switch (inner) {
        .unknown => unreachable,
        inline else => |*any_channel| try any_channel.patch(data),
    }

    self.meta.patch(.inner, inner);
}
