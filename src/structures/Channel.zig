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
    guild_text,
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

pub const Inner = union(Type) {
    guild_text: struct {},
    dm: struct {},
    guild_voice: struct {},
    group_dm: struct {},
    guild_category: struct {},
    guild_announcement: struct {},
    announcement_thread: struct {},
    public_thread: struct {},
    private_thread: struct {},
    guild_stage_voice: struct {},
    guild_directory: struct {},
    guild_forum: struct {},
    guild_media: struct {},
};

meta: QueriedFields(Channel, .{
    "inner",
}) = .none,

context: *Client,
id: Snowflake,

inner: Inner = .{ .guild_text = .{} },

pub fn deinit(self: *Channel) void {
    _ = self;
}

pub fn patch(self: *Channel, data: Data) !void {
    const @"type" = @as(Type, @enumFromInt(data.type));
    const inner = switch (@"type") {
        inline else => |tag| @unionInit(Inner, @tagName(tag), .{}),
    };

    self.meta.patch(.inner, inner);
}
