const std = @import("std");
const builtin = @import("builtin");

const Snowflake = @import("../snowflake.zig").Snowflake;
const QueriedFields = @import("../queryable.zig").QueriedFields;
const Client = @import("../Client.zig");

const ReactionAdd = Client.ReactionAdd;

const Channel = @import("Channel.zig");
const Guild = @import("Guild.zig");
const User = @import("User.zig");

const gateway_message = @import("../gateway_message.zig");

pub const Data = struct {
    base: gateway_message.Message,
    guild_id: ?gateway_message.Snowflake,
    member: ?gateway_message.Guild.Member,
    mentions: ?[]gateway_message.User,
};

const Message = @This();

const Type = enum(i32) {
    default,
    recipient_add,
    recipient_remove,
    call,
    channel_name_change,
    channel_icon_change,
    channel_pinned_message,
    user_join,
    guild_boost,
    guild_boost_tier_1,
    guild_boost_tier_2,
    guild_boost_tier_3,
    channel_follow_add,
    guild_discovery_disqualified,
    guild_discovery_requalified = 14,
    guild_discovery_grace_period_initial_warning,
    guild_discovery_grace_period_final_warning,
    thread_created,
    reply,
    chat_input_command,
    thread_starter_message,
    guild_invite_reminder,
    context_menu_command,
    auto_moderation_action,
    role_subscription_purchase,
    interaction_premium_resell,
    stage_start,
    stage_end,
    stage_speaker,
    stage_topic = 31,
    guild_application_premium_subscription,
    guild_incident_alert_mode_enabled = 36,
    guild_incident_alert_mode_disabled,
    guild_incident_report_raid,
    guild_incident_report_false_alarm,
    purchase_notification = 44,
    poll_result = 46,
};

pub const Flags = packed struct(i32) {
    crossposted: bool = false,
    is_crosspost: bool = false,
    suppress_embeds: bool = false,
    source_message_deleted: bool = false,
    urgent: bool = false,
    has_thread: bool = false,
    ephemeral: bool = false,
    loading: bool = false,
    failed_to_mention_some_roles_in_thread: bool = false,
    _packed1: enum(u3) { unset } = .unset,
    suppressed_notifications: bool = false,
    is_voice_message: bool = false,
    has_snapshot: bool = false,
    is_components_v2: bool = false,
    _packed2: enum(u15) { unset } = .unset,
};

// pub const Color = switch (builtin.target.cpu.arch.endian()) {
//     .little => packed struct(u24) {
//         b: u8,
//         g: u8,
//         r: u8,

//         pub fn jsonStringify(self: Color, jw: anytype) !void {
//             try jw.write(@as(u24, @bitCast(self)));
//         }
//     },
//     .big => packed struct(u24) {
//         r: u8,
//         g: u8,
//         b: u8,

//         pub fn jsonStringify(self: Color, jw: anytype) !void {
//             try jw.write(@as(u24, @bitCast(self)));
//         }
//     },
// };

pub const Color = packed struct(u24) {
    r: u8,
    g: u8,
    b: u8,

    pub fn jsonStringify(self: Color, jw: anytype) !void {
        try jw.write(std.mem.nativeTo(u24, @bitCast(self), .big));
    }
};

meta: QueriedFields(Message, &.{
    "guild",  "channel", "author",
    "member", "content",
}) = .none,

context: *Client,
id: Snowflake,

guild: *Guild = undefined,
channel: *Channel = undefined,
author: *User = undefined,
member: *Guild.Member = undefined,
content: []const u8 = "",

pub fn deinit(self: *Message) void {
    const allocator = self.context.allocator;
    allocator.free(self.content);
}

pub fn patch(self: *Message, data: Data) !void {
    const allocator = self.context.allocator;

    if (data.guild_id) |guild_id| {
        const guild = try self.context.guilds.cache.touch(self.context, try .resolve(guild_id));
        self.meta.patch(.guild, guild);

        if (data.member) |data_member| {
            const member = try guild.members.cache.patch(guild, try .resolve(data.base.author.id), data_member);
            try guild.members.pool.add(member);
            self.meta.patch(.member, member);
        }
    }

    const channel = try self.context.channels.cache.touch(self.context, try .resolve(data.base.channel_id));
    self.meta.patch(.channel, channel);

    const author = try self.context.users.cache.patch(self.context, try .resolve(data.base.author.id), data.base.author);
    self.meta.patch(.author, author);

    allocator.free(self.content);
    self.meta.patch(.content, try allocator.dupe(u8, data.base.content));
}

pub fn delete(self: *Message) !void {
    try self.context.deleteMessage(self.channel.id, self.id);
}

pub fn createReaction(self: *Message, reaction: ReactionAdd) !void {
    try self.context.createReaction(self.channel.id, self.id, reaction);
}
