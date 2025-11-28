const std = @import("std");

pub fn Elective(comptime Inner: type) type {
    return union(enum) {
        not_given: void,
        val: Inner,

        pub fn jsonParse(
            allocator: std.mem.Allocator,
            source: anytype,
            options: std.json.ParseOptions,
        ) !Elective(Inner) {
            return .{
                .val = try std.json.innerParse(Inner, allocator, source, options),
            };
        }

        pub fn jsonParseFromValue(
            allocator: std.mem.Allocator,
            source: std.json.Value,
            options: std.json.ParseOptions,
        ) !Elective(Inner) {
            return .{
                .val = try std.json.innerParseFromValue(Inner, allocator, source, options),
            };
        }
    };
}

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
                .heartbeat => payload.Heartbeat,
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

        pub fn jsonStringify(self: @This(), jw: anytype) !void {
            try jw.beginObject();
            try jw.objectField("op");
            try jw.write(self.op);
            try jw.objectField("d");
            try jw.write(self.d);
            if (self.s) |s| {
                try jw.objectField("s");
                try jw.write(s);
            }
            if (self.t) |t| {
                try jw.objectField("t");
                try jw.write(t);
            }
            try jw.endObject();
        }
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
pub const Entitlement = std.json.Value;

pub const User = struct {
    id: Snowflake,
    username: []const u8,
    discriminator: []const u8,
    global_name: ?[]const u8,
    avatar: ?[]const u8,
    bot: Elective(bool) = .not_given,
    system: Elective(bool) = .not_given,
    mfa_enabled: Elective(bool) = .not_given,
    banner: Elective(?[]const u8) = .not_given,
    accent_color: Elective(?i32) = .not_given,
    locale: Elective([]const u8) = .not_given,
    verified: Elective(bool) = .not_given,
    email: Elective(?[]const u8) = .not_given,
    flags: Elective(i32) = .not_given,
    premium_type: Elective(i32) = .not_given,
    public_flags: Elective(i32) = .not_given,
    avatar_decoration_data: Elective(?AvatarDecorationData) = .not_given,
};

pub const Role = struct {
    pub const Tag = struct {
        bot_id: Elective(Snowflake) = .not_given,
        integration_id: Elective(Snowflake) = .not_given,
        premium_subscriber: Elective(?bool) = .not_given,
        subscription_listing_id: Elective(Snowflake) = .not_given,
        available_for_purchase: Elective(?bool) = .not_given,
        guild_connections: Elective(?bool) = .not_given,
    };

    id: Snowflake,
    name: []const u8,
    color: i32,
    hoist: bool,
    icon: Elective(?[]const u8) = .not_given,
    unicode_emoji: Elective(?[]const u8) = .not_given,
    position: i32,
    permissions: Permissions,
    managed: bool,
    mentionable: bool,
    tags: Elective(Tag) = .not_given,
    flags: i32,
};

pub const Emoji = std.json.Value; // TODO

pub const Guild = struct {
    pub const Unavailable = struct {
        id: []const u8,
        unavailable: bool,
    };

    pub const Partial = struct {
        id: []const u8,
    };

    pub const Member = struct {
        user: Elective(User) = .not_given,
        nick: Elective(?[]const u8) = .not_given,
        avatar: Elective(?[]const u8) = .not_given,
        banner: Elective(?[]const u8) = .not_given,
        roles: []Snowflake,
        joined_at: Iso8601Timestamp,
        premium_since: Elective(?Iso8601Timestamp) = .not_given,
        deaf: bool,
        mute: bool,
        flags: i32,
        pending: Elective(bool) = .not_given,
        permissions: Elective(Permissions) = .not_given,
        communication_disabled_util: Elective(?Iso8601Timestamp) = .not_given,
        avatar_decoration_data: Elective(?AvatarDecorationData) = .not_given,
    };

    pub const Feature = std.json.Value; // TODO
    pub const WelcomeScreen = std.json.Value; // TODO
    pub const IncidentsData = std.json.Value; // TODO

    id: Snowflake,
    name: []const u8,
    icon: ?[]const u8,
    icon_hash: Elective(?[]const u8) = .not_given,
    splash: ?[]const u8,
    discovery_splash: ?[]const u8,
    owner: Elective(bool) = .not_given,
    owner_id: Snowflake,
    permissions: Elective(Permissions) = .not_given,
    region: Elective(?[]const u8) = .not_given,
    afk_channel_id: ?Snowflake,
    afk_timeout: i32,
    widget_enabled: Elective(bool) = .not_given,
    widget_channel_id: Elective(?Snowflake) = .not_given,
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
    max_presences: Elective(?i32) = .not_given,
    max_numbers: Elective(?i32) = .not_given,
    vanity_url_code: ?[]const u8,
    description: ?[]const u8,
    banner: ?[]const u8,
    premium_tier: i32,
    premium_subscription_count: i32,
    preferred_locale: []const u8,
    public_updates_channel_id: ?Snowflake,
    max_video_channel_users: Elective(i32) = .not_given,
    max_stage_video_channel_users: Elective(i32) = .not_given,
    approximate_member_count: Elective(i32) = .not_given,
    approximate_presence_count: Elective(i32) = .not_given,
    welcome_screen: Elective(WelcomeScreen) = .not_given,
    nsfw_level: i32,
    stickers: Elective([]Sticker) = .not_given,
    premium_progress_bar_enabled: bool,
    safety_alerts_channel_id: ?Snowflake,
    incidents_data: ?IncidentsData,
};

pub const Permissions = []const u8;

pub const PermissionsOverwrite = struct {
    id: Snowflake,
    type: i32,
    allow: Permissions,
    deny: Permissions,
};

pub const Channel = struct {
    pub const Mention = std.json.Value; // TODO

    pub const ThreadMetadata = struct {
        archived: bool,
        auto_archive_duration: i32,
        archive_timestamp: Iso8601Timestamp,
        locked: bool,
        invitable: Elective(bool) = .not_given,
        create_timestamp: Elective(?Iso8601Timestamp) = .not_given,
    };

    pub const ThreadMember = struct {
        id: Elective(Snowflake) = .not_given,
        user_id: Elective(Snowflake) = .not_given,
        join_timestamp: Iso8601Timestamp,
        flags: i32,
        member: Elective(Guild.Member) = .not_given,
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
    guild_id: Elective(Snowflake) = .not_given,
    position: Elective(i32) = .not_given,
    permission_overwrites: Elective([]PermissionsOverwrite) = .not_given,
    name: Elective(?[]const u8) = .not_given,
    topic: Elective(?[]const u8) = .not_given,
    nsfw: Elective(bool) = .not_given,
    last_message_id: Elective(?Snowflake) = .not_given,
    bitrate: Elective(i32) = .not_given,
    user_limit: Elective(i32) = .not_given,
    rate_limit_per_user: Elective(i32) = .not_given,
    recipients: Elective([]User) = .not_given,
    icon: Elective(?[]const u8) = .not_given,
    owner_id: Elective(Snowflake) = .not_given,
    application_id: Elective(Snowflake) = .not_given,
    managed: Elective(bool) = .not_given,
    parent_id: Elective(?Snowflake) = .not_given,
    last_pin_timestamp: Elective(?Iso8601Timestamp) = .not_given,
    rtc_region: Elective(?[]const u8) = .not_given,
    video_quality_mode: Elective(i32) = .not_given,
    message_count: Elective(i32) = .not_given,
    member_count: Elective(i32) = .not_given,
    thread_metadata: Elective(ThreadMetadata) = .not_given,
    member: Elective(ThreadMember) = .not_given,
    default_auto_archive_duration: Elective(i32) = .not_given,
    permissions: Elective(Permissions) = .not_given,
    flags: Elective(i32) = .not_given,
    total_message_sent: Elective(i32) = .not_given,
    available_tags: Elective([]ForumTag) = .not_given,
    applied_tags: Elective([]Snowflake) = .not_given,
    default_reaction_emoji: Elective(?Reaction.Default) = .not_given,
    default_thread_rate_limit_per_user: Elective(i32) = .not_given,
    default_sort_order: Elective(?i32) = .not_given,
    default_forum_layout: Elective(i32) = .not_given,
};

pub const Attachment = std.json.Value; // TODO
pub const Embed = struct {
    pub const Footer = struct {
        text: []const u8,
        icon_url: Elective([]const u8) = .not_given,
        proxy_icon_url: Elective([]const u8) = .not_given,
    };

    pub const Image = struct {
        url: []const u8,
        proxy_url: Elective([]const u8) = .not_given,
        height: Elective(i32) = .not_given,
        width: Elective(i32) = .not_given,
    };

    pub const Thumbnail = struct {
        url: []const u8,
        proxy_url: Elective([]const u8) = .not_given,
        height: Elective(i32) = .not_given,
        width: Elective(i32) = .not_given,
    };

    pub const Video = struct {
        url: Elective([]const u8) = .not_given,
        proxy_url: Elective([]const u8) = .not_given,
        height: Elective(i32) = .not_given,
        width: Elective(i32) = .not_given,
    };

    pub const Provider = struct {
        name: Elective([]const u8) = .not_given,
        url: Elective([]const u8) = .not_given,
    };

    pub const Author = struct {
        name: []const u8,
        url: Elective([]const u8) = .not_given,
        icon_url: Elective([]const u8) = .not_given,
        proxy_icon_url: Elective([]const u8) = .not_given,
    };

    pub const Field = struct {
        name: []const u8,
        value: []const u8,
        @"inline": Elective(bool) = .not_given,
    };

    title: Elective([]const u8) = .not_given,
    type: Elective([]const u8) = .not_given,
    description: Elective([]const u8) = .not_given,
    url: Elective([]const u8) = .not_given,
    timestamp: Elective(Iso8601Timestamp) = .not_given,
    color: Elective(i32) = .not_given,
    footer: Elective(Footer) = .not_given,
    image: Elective(Image) = .not_given,
    thumbnail: Elective(Thumbnail) = .not_given,
    video: Elective(Video) = .not_given,
    provider: Elective(Provider) = .not_given,
    author: Elective(Author) = .not_given,
    fields: Elective([]Field) = .not_given,
}; // TODO

pub const Reaction = struct {
    pub const Default = struct {
        emoji_id: ?Snowflake,
        emoji_name: ?[]const u8,
    };

    count: i32,
    count_details: std.json.Value, //TODO
    me: bool,
    me_burst: bool,
    emoji: Emoji, // TOOD: partial emoji
    burst_colors: std.json.Value,
};

pub const Sticker = std.json.Value; // TODO
pub const RoleSubscriptionData = std.json.Value; // TODO

pub const Message = struct {
    pub const Type = i32;

    pub const Activity = struct {
        type: i32,

        party_id: Elective([]const u8) = .not_given,
    };

    pub const Reference = struct {
        type: Elective(i32) = .not_given,
        message_id: Elective(Snowflake) = .not_given,
        channel_id: Elective(Snowflake) = .not_given,
        guild_id: Elective(Snowflake) = .not_given,
        fail_if_not_exists: Elective(bool) = .not_given,
    };

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
    mention_channels: Elective([]Channel.Mention) = .not_given,
    attachments: []Attachment,
    embeds: []Embed,
    reactions: Elective([]Reaction) = .not_given,
    nonce: Elective(std.json.Value) = .not_given,
    pinned: bool,
    webhook_id: Elective(Snowflake) = .not_given,
    type: Type,
    activity: Elective(Activity) = .not_given,
    application: Elective(Application) = .not_given, // TODO: only a 'partial' application
    application_id: Elective(Snowflake) = .not_given,
    flags: Elective(i32) = .not_given,
    message_reference: Elective(Reference) = .not_given,
    message_snapshots: Elective([]Snapshot) = .not_given,
    referenced_message: Elective(?*Message) = .not_given,
    interaction_metadata: Elective(InteractionMetadata) = .not_given,
    thread: Elective(Channel) = .not_given,
    components: Elective([]Component) = .not_given,
    sticker_items: Elective([]StickerItem) = .not_given,
    stickers: Elective([]Sticker) = .not_given,
    position: Elective(i32) = .not_given,
    role_subscription_data: Elective(RoleSubscriptionData) = .not_given,
    resolved: Elective(Resolved) = .not_given,
    poll: Elective(Poll) = .not_given,
    call: Elective(Call) = .not_given,
};

pub const Interaction = struct {
    pub const ApplicationCommandData = struct {
        id: Snowflake,
        name: []const u8,
        type: i32,
        resolved: Elective(std.json.Value) = .not_given, // todo: parse fully
        options: Elective(std.json.Value) = .not_given, // todo: parse fully
        guild_id: Elective(Snowflake) = .not_given,
        target_id: Elective(Snowflake) = .not_given,
    };

    pub const MessageComponentData = struct {
        custom_id: []const u8,
        component_type: i32,
        values: Elective(std.json.Value) = .not_given, // todo: parse fully
        resolved: Elective(std.json.Value) = .not_given, // todo: parse fully
    };

    id: Snowflake,
    application_id: Snowflake,
    type: i32,
    data: Elective(std.json.Value) = .not_given,
    guild: Elective(Guild.Partial) = .not_given,
    guild_id: Elective(Snowflake) = .not_given,
    channel: Elective(Channel) = .not_given,
    channel_id: Elective(Snowflake) = .not_given,
    member: Elective(Guild.Member) = .not_given,
    user: Elective(Guild.Member) = .not_given,
    token: []const u8,
    version: i32,
    message: Elective(Message) = .not_given,
    app_permissions: []const u8,
    locale: Elective([]const u8) = .not_given,
    guild_locale: Elective([]const u8) = .not_given,
    entitlements: []Entitlement,
    authorizing_integration_owners: std.json.Value, // todo: what is this field? https://discord.com/developers/docs/interactions/receiving-and-responding#interaction-object-interaction-structure
    context: Elective(i32) = .not_given,
    attachment_size_limit: i32,
};

pub const payload = struct {
    pub const Hello = struct {
        heartbeat_interval: i32,
    };

    pub const Heartbeat = ?usize;

    pub const Identify = struct {
        pub const Properties = struct {
            os: []const u8,
            browser: []const u8,
            device: []const u8,
        };

        token: []const u8,
        properties: Properties,
        compress: Elective(bool) = .not_given,
        large_threshold: Elective(i32) = .not_given,
        shard: Elective(Sharding) = .not_given,
        // presence: Presence, TODO
        intents: i32,

        pub fn jsonStringify(self: Identify, jw: anytype) !void {
            try jw.beginObject();
            try jw.objectField("token");
            try jw.write(self.token);
            try jw.objectField("properties");
            try jw.write(self.properties);
            switch (self.compress) {
                .not_given => {},
                .val => |compress| {
                    try jw.objectField("compress");
                    try jw.write(compress);
                },
            }
            switch (self.large_threshold) {
                .not_given => {},
                .val => |large_threshold| {
                    try jw.objectField("large_threshold");
                    try jw.write(large_threshold);
                },
            }
            switch (self.shard) {
                .not_given => {},
                .val => |sharding| {
                    try jw.objectField("shard");
                    try jw.beginArray();
                    try jw.write(sharding.shard_id);
                    try jw.write(sharding.num_shards);
                    try jw.endArray();
                },
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
        shard: Elective(Sharding) = .not_given,
        application: struct {
            id: Snowflake,
            flags: i32,
        },
    };

    pub const UserUpdate = User;

    pub const GuildCreate = union(enum) {
        pub const Available = struct {
            pub const Extra = struct {
                joined_at: Iso8601Timestamp,
                large: bool,
                unavailable: Elective(bool) = .not_given,
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

    pub const GuildMemberAdd = struct {
        pub const Extra = struct {
            guild_id: Snowflake,
        };

        inner_guild_member: Guild.Member,
        extra: Extra,

        pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !GuildMemberAdd {
            const inner_guild_member = try std.json.innerParseFromValue(Guild.Member, allocator, source, options);
            const extra = try std.json.innerParseFromValue(Extra, allocator, source, options);

            return .{
                .inner_guild_member = inner_guild_member,
                .extra = extra,
            };
        }
    };

    pub const GuildMemberRemove = struct {
        guild_id: Snowflake,
        user: User,
    };

    pub const GuildMemberUpdate = struct {
        guild_id: Snowflake,
        roles: []Snowflake,
        user: User,
        nick: Elective(?[]const u8) = .not_given,
        avatar: ?[]const u8,
        banner: ?[]const u8,
        joined_at: ?Iso8601Timestamp,
        premium_since: Elective(?Iso8601Timestamp) = .not_given,
        deaf: Elective(bool) = .not_given,
        mute: Elective(bool) = .not_given,
        pending: Elective(bool) = .not_given,
        communication_disabled_until: Elective(?Iso8601Timestamp) = .not_given,
        flags: Elective(i32) = .not_given,
        avatar_decoration_data: Elective(?AvatarDecorationData) = .not_given,
    };

    pub const MessageCreate = struct {
        pub const Extra = struct {
            guild_id: Elective(Snowflake) = .not_given,
            member: Elective(Guild.Member) = .not_given,
            mentions: []User, // TODO: each user also contains a 'member' field containing a partial guild member
        };

        inner_message: Message,
        extra: Extra,

        pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !MessageCreate {
            const inner_message = try std.json.innerParseFromValue(Message, allocator, source, options);
            const extra = try std.json.innerParseFromValue(Extra, allocator, source, options);

            return .{
                .inner_message = inner_message,
                .extra = extra,
            };
        }
    };

    pub const MessageDelete = struct {
        id: Snowflake,
        channel_id: Snowflake,
        guild_id: Elective(Snowflake) = .not_given,
    };

    pub const MessageUpdate = MessageCreate;

    pub const InteractionCreate = Interaction;
};
