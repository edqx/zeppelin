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

const MessageBuilder = @import("../MessageBuilder.zig");

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
    guild_discovery_disqualified = 14,
    guild_discovery_requalified,
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

pub const ReferenceType = enum(i32) {
    reply = 0,
    forward = 1,
};

pub const Reference = union(ReferenceType) {
    reply: *Message,
    forward: *Message,
};

meta: QueriedFields(Message, &.{
    "type",   "guild",   "channel",   "author",
    "member", "content", "reference",
}) = .none,

context: *Client,
id: Snowflake,

type: Type = .default,

guild: *Guild = undefined,
channel: *Channel = undefined,
author: *User = undefined,
member: *Guild.Member = undefined,
content: []const u8 = "",

reference: ?Reference = null,

pub fn deinit(self: *Message) void {
    const allocator = self.context.allocator;
    allocator.free(self.content);
}

pub fn patch(self: *Message, data: Data) !void {
    const allocator = self.context.allocator;

    self.meta.patch(.type, @enumFromInt(data.base.type));

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

    std.log.info("type: {}", .{self.type});

    if (self.type == .reply) {
        switch (data.base.message_reference) {
            .not_given => {},
            .val => |reference_data| patch_reference: {
                const reference_type: ReferenceType = switch (reference_data.type) {
                    .not_given => .reply,
                    .val => |ref_int| @enumFromInt(ref_int),
                };

                const message_id: Snowflake = switch (reference_data.message_id) {
                    .not_given => break :patch_reference,
                    .val => |message_id_data| try .resolve(message_id_data),
                };

                const message = try self.context.messages.cache.touch(self.context, message_id);

                switch (reference_data.guild_id) {
                    .not_given => {},
                    .val => |guild_id_data| {
                        const ref_guild = try self.context.guilds.cache.touch(self.context, try .resolve(guild_id_data));
                        message.meta.patch(.guild, ref_guild);
                    },
                }

                switch (reference_data.channel_id) {
                    .not_given => {},
                    .val => |channel_id_data| {
                        const ref_channel = try self.context.channels.cache.touch(self.context, try .resolve(channel_id_data));
                        message.meta.patch(.channel, ref_channel);
                    },
                }

                switch (data.base.referenced_message) {
                    .not_given => {},
                    .val => |maybe_referenced_message_data| {
                        if (maybe_referenced_message_data) |referenced_message_data| {
                            try message.patch(.{
                                .base = referenced_message_data.*,
                                .guild_id = null,
                                .member = null,
                                .mentions = null,
                            });
                        } else {
                            // message was deleted
                        }
                    },
                }

                self.meta.patch(.reference, switch (reference_type) {
                    .reply => .{ .reply = message },
                    .forward => .{ .forward = message },
                });
            },
        }
    } else {
        self.meta.patch(.reference, null);
    }
}

pub fn delete(self: *Message) !void {
    try self.context.deleteMessage(self.channel.id, self.id);
}

pub fn createReaction(self: *Message, reaction: ReactionAdd) !void {
    try self.context.createReaction(self.channel.id, self.id, reaction);
}

pub fn startThread(self: *Message, name: []const u8, options: Client.StartThreadOptions) !*Channel {
    return try self.context.startThreadFromMessage(self.channel.id, self.id, name, options);
}

pub fn createReplyMessage(self: *Message, message_builder: MessageBuilder, options: Client.MessageWriter.Options) !*Message {
    std.debug.assert(options.reference == null);
    var new_options = options;
    new_options.reference = .{ .reply_to = self.id };
    return try self.context.createMessage(self.channel.id, message_builder, new_options);
}

pub fn replyMessageWriter(self: *Message, options: Client.MessageWriter.Options) !*Client.MessageWriter {
    std.debug.assert(options.reference == null);
    var new_options = options;
    new_options.reference = .{ .reply_to = self.id };
    return try self.context.messageWriter(self.channel.id, new_options);
}
