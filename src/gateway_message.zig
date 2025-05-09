const std = @import("std");

pub const opcode = struct {
    pub const Receive = enum(u32) {
        dispatch = 0,
        heartbeat = 1,
        reconnect = 7,
        invalid_session = 9,
        hello = 10,
        heartbeat_acknowledge = 11,
    };

    pub const Send = enum(u32) {
        heartbeat = 1,
        identify = 2,
        presence_update = 3,
        voice_state_update = 4,
        @"resume" = 6,
        request_guild_members = 8,
        request_soundboard_sounds = 31,

        pub fn Payload(comptime self: opcode.Send) type {
            return switch (self) {
                .identify => payload.Identify,
                else => @compileError("Unsupported payload type for send opcode " ++ @tagName(self)),
            };
        }
    };

    pub const Close = enum(u32) {
        unknown_error = 4000,
        unknown_opcode = 4001,
        decode_error = 4002,
        not_authenticated = 4003,
        authentication_failed = 4004,
        already_authenticated = 4005,
        invalid_sequence = 4007,
        rate_limited = 4008,
        session_timed_out = 4009,
        invalid_shard = 4010,
        sharding_required = 4011,
        invalid_api_version = 4012,
        invalid_intents = 4013,
        disallowed_intents = 4014,

        pub fn reconnect(self: Close) bool {
            return switch (self) {
                .unknown_error,
                .unknown_opcode,
                .decode_error,
                .not_authenticated,
                .already_authenticated,
                .invalid_sequence,
                .rate_limited,
                .session_timed_out,
                => true,
                .authentication_failed,
                .invalid_shard,
                .sharding_required,
                .invalid_api_version,
                .invalid_intents,
                .disallowed_intents,
                => false,
            };
        }
    };
};

pub const Receive = struct {
    op: i32,
    d: ?std.json.Value,
    s: ?i32,
    t: ?[]const u8,
};

pub fn Send(comptime Payload: type) type {
    return struct {
        op: i32,
        d: Payload,
        s: ?i32 = null,
        t: ?[]const u8 = null,
    };
}

pub const Snowflake = []const u8;
pub const Iso8601Timestamp = []const u8;

pub const Sharding = struct {
    shard_id: i32,
    num_shards: i32,
};

pub const AvatarDecorationData = struct {
    asset: []const u8,
    sku_id: Snowflake,
};

pub const Application = std.json.Value; // TODO

pub const User = struct {
    id: Snowflake,
    username: []const u8,
    discriminator: []const u8,
    global_name: ?[]const u8,
    avatar: ?[]const u8,
    bot: ?bool = null,
    system: ?bool = null,
    mfa_enabled: ?bool = null,
    banner: ??[]const u8 = null,
    accent_color: ??i32 = null,
    locale: ?[]const u8 = null,
    verified: ?bool = null,
    email: ??[]const u8 = null,
    flags: ?i32 = null,
    premium_type: ?i32 = null,
    public_flags: ?i32 = null,
    avatar_decoration_data: ??AvatarDecorationData = null,
};

pub const Role = std.json.Value; // TODO
pub const Emoji = std.json.Value; // TODO

pub const Guild = struct {
    pub const Unavailable = struct {
        id: []const u8,
        unavailable: bool,
    };

    pub const Feature = std.json.Value; // TODO
    pub const Member = std.json.Value; // TODO
    pub const WelcomeScreen = std.json.Value; // TODO
    pub const IncidentsData = std.json.Value; // TODO

    id: Snowflake,
    name: []const u8,
    icon: ?[]const u8,
    icon_hash: ??[]const u8 = null,
    splash: ?[]const u8,
    discovery_splash: ?[]const u8,
    owner: ?bool = null,
    owner_id: Snowflake,
    permissions: ?[]const u8 = null,
    region: ??[]const u8 = null,
    afk_channel_id: ?Snowflake,
    afk_timeout: i32,
    widget_enabled: ?bool = null,
    widget_channel_id: ??Snowflake = null,
    verification_level: i32,
    default_message_notifications: i32,
    explicit_content_filter: i32,
    roles: []Role,
    emojis: []Emoji,
    features: []Feature,
    mfa_level: i32,
    application_id: ?Snowflake,
    system_channel_id: ?Snowflake,
    system_channel_flags: i32,
    rules_channel_id: ?Snowflake,
    max_presences: ??i32 = null,
    max_numbers: ??i32 = null,
    vanity_url_code: ?[]const u8,
    description: ?[]const u8,
    banner: ?[]const u8,
    premium_tier: i32,
    premium_subscription_count: i32,
    preferred_locale: []const u8,
    public_updates_channel_id: ?Snowflake,
    max_video_channel_users: ?i32 = null,
    max_stage_video_channel_users: ?i32 = null,
    approximate_member_count: ?i32 = null,
    approximate_presence_count: ?i32 = null,
    welcome_screen: ?WelcomeScreen = null,
    nsfw_level: i32,
    stickers: ?[]Sticker = null,
    premium_progress_bar_enabled: bool,
    safety_alerts_channel_id: ?Snowflake,
    incidents_data: ?IncidentsData,
};

pub const Permission = struct {
    pub const Overwrite = struct {
        id: Snowflake,
        type: i32,
        allow: []const u8,
        deny: []const u8,
    };
};

pub const Channel = struct {
    pub const Mention = std.json.Value; // TODO

    pub const ThreadMetadata = struct {
        archived: bool,
        auto_archive_duration: i32,
        archive_timestamp: Iso8601Timestamp,
        locked: bool,
        invitable: ?bool,
        create_timestamp: ??Iso8601Timestamp,
    };

    pub const ThreadMember = struct {
        id: ?Snowflake = null,
        user_id: ?Snowflake = null,
        join_timestamp: Iso8601Timestamp,
        flags: i32,
        member: ?Guild.Member = null,
    };

    pub const ForumTag = struct {
        id: Snowflake,
        name: []const u8,
        moderated: bool,
        emoji_id: ?Snowflake,
        emoji_name: ?[]const u8,
    };

    id: Snowflake,
    type: i32,
    guild_id: ?Snowflake = null,
    position: ?i32 = null,
    permission_overwrites: ?[]Permission.Overwrite = null,
    name: ??[]const u8 = null,
    topic: ??[]const u8 = null,
    nsfw: ?bool = null,
    last_message_id: ??Snowflake = null,
    bitrate: ?i32 = null,
    user_limit: ?i32 = null,
    rate_limit_per_user: ?i32 = null,
    recipients: ?[]User = null,
    icon: ??[]const u8 = null,
    owner_id: ?Snowflake = null,
    application_id: ?Snowflake = null,
    managed: ?bool = null,
    parent_id: ??Snowflake = null,
    last_pin_timestamp: ??Iso8601Timestamp = null,
    rtc_region: ??[]const u8 = null,
    video_quality_mode: ?i32 = null,
    message_count: ?i32 = null,
    member_count: ?i32 = null,
    thread_metadata: ?ThreadMetadata = null,
    member: ?ThreadMember = null,
    default_auto_archive_duration: ?i32 = null,
    permissions: ?[]const u8 = null,
    flags: ?i32 = null,
    total_message_sent: ?i32 = null,
    available_tags: ?[]ForumTag = null,
    applied_tags: ?[]Snowflake = null,
    default_reaction_emoji: ??Reaction.Default = null,
    default_thread_rate_limit_per_user: ?i32 = null,
    default_sort_order: ??i32 = null,
    default_forum_layout: ?i32 = null,
};

pub const Attachment = std.json.Value; // TODO
pub const Embed = std.json.Value; // TODO
pub const Reaction = struct {
    pub const Default = struct {
        emoji_id: ?Snowflake,
        emoji_name: ?[]const u8,
    };

    // TODO
};

pub const Sticker = std.json.Value; // TODO
pub const RoleSubscriptionData = std.json.Value; // TODO

pub const Message = struct {
    pub const Type = i32;

    pub const Activity = struct {
        type: i32,

        party_id: ?[]const u8 = null,
    };

    pub const Reference = std.json.Value; // TODO
    pub const Snapshot = std.json.Value; // TODO
    pub const InteractionMetadata = std.json.Value; // TODO
    pub const Component = std.json.Value; // TODO
    pub const StickerItem = std.json.Value; // TODO
    pub const Resolved = std.json.Value; // TODO
    pub const Poll = std.json.Value; // TODO
    pub const Call = std.json.Value; // TODO

    id: Snowflake,
    channel_id: []const u8,
    author: User,
    content: []const u8,
    timestamp: Iso8601Timestamp,
    edited_timestamp: ?Iso8601Timestamp,
    tts: bool,
    mention_everyone: bool,
    mentions: []User,
    mention_roles: []Role,
    mention_channels: ?[]Channel.Mention = null,
    attachments: []Attachment,
    embeds: []Embed,
    reactions: ?[]Reaction = null,
    nonce: ?std.json.Value = null,
    pinned: bool,
    webhook_id: ?Snowflake = null,
    type: Type,
    activity: ?Activity = null,
    application: ?Application = null, // TODO: only a 'partial' application
    application_id: ?Snowflake = null,
    flags: ?i32 = null,
    message_reference: ?Reference = null,
    message_snapshots: ?[]Snapshot = null,
    referenced_message: ??*Message = null,
    interaction_metadata: ?InteractionMetadata = null,
    thread: ?Channel = null,
    components: ?[]Component = null,
    sticker_items: ?[]StickerItem = null,
    stickers: ?[]Sticker = null,
    position: ?i32 = null,
    role_subscription_data: ?RoleSubscriptionData = null,
    resolved: ?Resolved = null,
    poll: ?Poll = null,
    call: ?Call = null,
};

pub const payload = struct {
    pub const Hello = struct {
        heartbeat_interval: i32,
    };

    pub const Identify = struct {
        pub const Properties = struct {
            os: []const u8,
            browser: []const u8,
            device: []const u8,
        };

        token: []const u8,
        properties: Properties,
        compress: ?bool = null,
        large_threshold: ?i32 = null,
        shard: ?Sharding = null,
        // presence: Presence, TODO
        intents: i32,

        pub fn jsonStringify(self: Identify, jw: anytype) !void {
            try jw.beginObject();
            try jw.objectField("token");
            try jw.write(self.token);
            try jw.objectField("properties");
            try jw.write(self.properties);
            if (self.compress) |compress| {
                try jw.objectField("compress");
                try jw.write(compress);
            }
            if (self.large_threshold) |large_threshold| {
                try jw.objectField("large_threshold");
                try jw.write(large_threshold);
            }
            if (self.shard) |sharding| {
                try jw.objectField("shard");
                try jw.beginArray();
                try jw.write(sharding.shard_id);
                try jw.write(sharding.num_shards);
                try jw.endArray();
            }
            try jw.objectField("intents");
            try jw.write(self.intents);
            try jw.endObject();
        }
    };

    pub const Ready = struct {
        v: i32,
        user: User,
        guilds: []Guild.Unavailable,
        session_id: []const u8,
        resume_gateway_url: []const u8,
        shard: ?Sharding = null,
        application: struct {
            id: Snowflake,
            flags: i32,
        },
    };

    pub const GuildCreate = union(enum) {
        pub const Available = struct {
            pub const Extra = struct {
                joined_at: Iso8601Timestamp,
                large: bool,
                unavailable: ?bool = null,
                member_count: i32,
                voice_states: []std.json.Value, // TODO
                members: []Guild.Member,
                channels: []Channel,
                presences: []std.json.Value, // TODO
                stage_instances: []std.json.Value, // TODO
                guild_scheduled_events: []std.json.Value, // TODO
                soundboard_sounds: []std.json.Value, // TODO
            };

            inner_guild: Guild,
            extra: Extra,

            pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !GuildCreate.Available {
                const inner_guild = try std.json.innerParseFromValue(Guild, allocator, source, options);
                const extra = try std.json.innerParseFromValue(@FieldType(GuildCreate.Available, "extra"), allocator, source, options);

                return .{
                    .inner_guild = inner_guild,
                    .extra = extra,
                };
            }
        };

        available: Available,
        unavailable: Guild.Unavailable,

        pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !GuildCreate {
            if (source != .object) return std.json.ParseFromValueError.UnexpectedToken;
            const unavailable = source.object.get("unavailable") orelse return std.json.ParseFromValueError.MissingField;
            if (unavailable != .bool) return std.json.ParseFromValueError.UnexpectedToken;

            return if (unavailable.bool) .{
                .unavailable = try std.json.innerParseFromValue(Guild.Unavailable, allocator, source, options),
            } else .{
                .available = try std.json.innerParseFromValue(GuildCreate.Available, allocator, source, options),
            };
        }
    };

    pub const MessageCreate = struct {
        pub const Extra = struct {
            guild_id: ?Snowflake = null,
            member: ?std.json.Value = null, // TODO: contains partial member
            mentions: []User, // TODO: each user also contains a 'member' field containing a partial guild member
        };

        inner_message: Message,
        extra: Extra,

        pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !MessageCreate {
            const inner_message = try std.json.innerParseFromValue(Message, allocator, source, options);
            const extra = try std.json.innerParseFromValue(@FieldType(MessageCreate, "extra"), allocator, source, options);

            return .{
                .inner_message = inner_message,
                .extra = extra,
            };
        }
    };
};
