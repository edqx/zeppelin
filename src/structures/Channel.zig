const std = @import("std");

const Snowflake = @import("../snowflake.zig").Snowflake;
const QueriedFields = @import("../queryable.zig").QueriedFields;
const Client = @import("../Client.zig");

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

        id: Snowflake,
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

        pub fn createMessage(self: *AnyChannelT, content: []const u8) !*Message {
            const url = try std.fmt.allocPrint(self.context.allocator, "https://discord.com/api/v10/channels/{}/messages", .{self.id});
            defer self.context.allocator.free(url);

            var req = try self.context.rest_client.create(.POST, try std.Uri.parse(url));
            defer req.deinit();

            try req.begin("application/json");

            var json_writer = std.json.writeStream(req.writer(), .{});
            defer json_writer.deinit();

            try json_writer.beginObject();

            try json_writer.objectField("content");
            try json_writer.write(content);

            try json_writer.endObject();

            var arena: std.heap.ArenaAllocator = .init(self.context.allocator);
            defer arena.deinit();

            const message_response = try req.fetchJson(arena.allocator(), gateway_message.Message);

            return try self.context.global_cache.messages.patch(self.context, try .resolve(message_response.id), message_response);
        }
    };
}

pub const Inner = union(Type) {
    const in_guild: []const [:0]const u8 = &.{"guild"};
    const has_name: []const [:0]const u8 = &.{"name"};

    unknown: void,
    guild_text: AnyChannel(in_guild ++ has_name),
    dm: AnyChannel(&.{}),
    guild_voice: AnyChannel(in_guild ++ has_name),
    group_dm: AnyChannel(has_name),
    guild_category: AnyChannel(in_guild ++ has_name),
    guild_announcement: AnyChannel(in_guild ++ has_name),
    announcement_thread: AnyChannel(in_guild ++ has_name),
    public_thread: AnyChannel(in_guild ++ has_name),
    private_thread: AnyChannel(in_guild ++ has_name),
    guild_stage_voice: AnyChannel(in_guild ++ has_name),
    guild_directory: AnyChannel(in_guild ++ has_name),
    guild_forum: AnyChannel(in_guild ++ has_name),
    guild_media: AnyChannel(in_guild ++ has_name),
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
            .id = self.id,
        }),
    };

    switch (inner) {
        .unknown => unreachable,
        inline else => |*any_channel| try any_channel.patch(data),
    }

    self.meta.patch(.inner, inner);
}
