const std = @import("std");

const Snowflake = @import("../snowflake.zig").Snowflake;
const Queryable = @import("../queryable.zig").Queryable;
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

context: *Client,
id: Snowflake,
received: bool,

type: Type = .guild_text,
guild: ?Queryable(*Guild) = null,
position: ?i32 = null,
permission_overwrites: ?Queryable([]PermissionOverwrite) = null,
name: ?Queryable(?[]const u8) = null,
topic: ?Queryable([]const u8) = null,
nsfw: ?Queryable(bool) = null,
last_message: ?Queryable(?*Message) = null,
bitrate: ?Queryable(i32) = null,
user_limit: ?Queryable(i32) = null,
rate_limit_per_user: ?Queryable(i32) = null,
recipients: ?Queryable([]*User) = null,
icon_hash: ?Queryable(?[]const u8) = null,
owner: ?Queryable(*User) = null,
application_id: ?Queryable(Snowflake) = null, // TODO: application reference
managed: ?Queryable(bool) = null,
parent: ?Queryable(?*Channel) = null,
last_pin_timestamp: ?Queryable(?[]const u8) = null, // pin
rtc_region: ?Queryable(?[]const u8) = null,
video_quality_mode: ?Queryable(i32) = null,
message_count: ?Queryable(i32) = null,
member_count: ?Queryable(i32) = null,
thread_metadata: ?Queryable(void) = null, // TODO
member: ?Queryable(void) = null, // TODO
default_auto_archive_duration: ?Queryable(i32) = null,
permissions: ?Queryable(void) = null, // TODO: permission bitfield?
flags: ?Queryable(i32) = null,
total_message_sent: ?Queryable(i32) = null,
available_tags: ?Queryable(void) = null, // TODO: tag objects
applied_tags: ?Queryable(void) = null, // TODO: tag objects
default_reaction_emoji: ?Queryable(void) = null, // TODO: default reaction
default_thread_rate_limit_per_user: ?Queryable(i32) = null,
default_sort_order: ?Queryable(?i32) = null,
default_forum_layout: ?Queryable(?i32) = null,

pub fn deinit(self: *Channel) void {
    if (self.name) |queryable_name| if (queryable_name == .known) if (queryable_name.known) |name| {
        self.context.allocator.free(name);
    };
    if (self.topic == .known) self.context.allocator.free(self.topic.known);
    if (self.icon_hash == .known) if (self.icon_hash.known) |icon_hash| self.context.allocator.free(icon_hash);
    if (self.last_pin_timestamp == .known) if (self.last_pin_timestamp.known) |last_pin_timestamp| self.context.allocator.free(last_pin_timestamp);
    if (self.rtc_region == .known) if (self.rtc_region.known) |rtc_region| self.context.allocator.free(rtc_region);
}

pub fn patch(self: *Channel, data: Data) !void {
    self.type = @enumFromInt(data.type);

    var has_name: bool = false;
    var has_guild: bool = false;

    switch (self.type) {
        .guild_announcement,
        .guild_category,
        .guild_directory,
        .guild_forum,
        .guild_media,
        .guild_stage_voice,
        .guild_text,
        .guild_voice,
        .announcement_thread,
        .private_thread,
        .public_thread,
        => {
            has_name = true;
            has_guild = true;
        },
        .group_dm => {
            has_name = true;
        },
        .dm => {},
    }

    if (has_name) {
        if (self.name) |queryable_name| if (queryable_name == .known) if (queryable_name.known) |name| {
            self.context.allocator.free(name);
        };
        self.name = if (data.name) |maybe_name| if (maybe_name) |name| .{
            .known = try self.context.allocator.dupe(u8, name),
        } else .{ .known = null } else .unknown;
    } else {
        self.name = null;
    }

    if (has_guild) {
        self.guild = if (data.guild_id) |guild_id|
            .{ .known = try self.context.global_cache.guilds.touch(self.context, try .resolve(guild_id)) }
        else
            .unknown;
    } else {
        self.guild = null;
    }
}
