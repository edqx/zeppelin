const std = @import("std");

const Snowflake = @import("../snowflake.zig").Snowflake;
const Queryable = @import("../queryable.zig").Queryable;
const GlobalCache = @import("../Client.zig").GlobalCache;

const User = @import("User.zig");

pub const Data = @import("../gateway_message.zig").Message;

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

id: Snowflake,
content: []const u8,
author: *User,

pub fn init(self: *Message, cache: *GlobalCache, gpa: std.mem.Allocator, data: Data) !void {
    self.id = try .resolve(data.id);
    self.content = "";
    self.author = try cache.users.patch(cache, data.author);
    try self.patch(cache, gpa, data);
}

pub fn deinit(self: *Message, gpa: std.mem.Allocator) void {
    gpa.free(self.content);
}

pub fn patch(self: *Message, cache: *GlobalCache, gpa: std.mem.Allocator, data: Data) !void {
    gpa.free(self.content);
    self.content = try gpa.dupe(u8, data.content);
    self.author = try cache.users.patch(cache, data.author);
}
