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

// A modified version of std.json.innerJsonParseFromValue that allows structs to distinguish
// between non-existent fields and null values.
fn modifiedJsonParseFromValue(
    comptime T: type,
    allocator: std.mem.Allocator,
    source: std.json.Value,
    options: std.json.ParseOptions,
) !T {
    const struct_info = @typeInfo(T).@"struct";

    if (source != .object) return error.UnexpectedToken;

    var r: T = undefined;
    var fields_seen = [_]bool{false} ** struct_info.fields.len;

    var it = source.object.iterator();
    while (it.next()) |kv| {
        const field_name = kv.key_ptr.*;

        inline for (struct_info.fields, 0..) |field, i| {
            if (comptime std.mem.startsWith(u8, field.name, "_has_")) continue;

            if (field.is_comptime) @compileError("comptime fields are not supported: " ++ @typeName(T) ++ "." ++ field.name);
            if (std.mem.eql(u8, field.name, field_name)) {
                std.debug.assert(!fields_seen[i]); // Can't have duplicate keys in a Value.object.
                @field(r, field.name) = try std.json.innerParseFromValue(field.type, allocator, kv.value_ptr.*, options);
                if (@hasField(T, "_has_" ++ field.name)) {
                    @field(r, "_has_" ++ field.name) = true;
                }
                fields_seen[i] = true;
                break;
            }
        } else {
            if (!options.ignore_unknown_fields) return error.UnknownField;
        }
    }

    inline for (struct_info.fields, 0..) |field, i| {
        if (comptime std.mem.startsWith(u8, field.name, "_has_")) continue;
        if (!fields_seen[i]) {
            if (field.defaultValue()) |default| {
                @field(r, field.name) = default;
            } else {
                if (@hasField(T, "_has_" ++ field.name)) {
                    @field(r, "_has_" ++ field.name) = false;
                } else {
                    return error.MissingField;
                }
            }
        }
    }

    return r;
}

pub const Snowflake = []const u8;

pub const Sharding = struct {
    shard_id: i32,
    num_shards: i32,
};

pub const AvatarDecorationData = struct {
    asset: []const u8,
    sku_id: Snowflake,
};

pub const User = struct {
    id: Snowflake,
    username: []const u8,
    discriminator: []const u8,
    global_name: ?[]const u8,
    avatar: ?[]const u8,

    _has_bot: bool,
    bot: bool,

    _has_system: bool,
    system: bool,

    _has_mfa_enabled: bool,
    mfa_enabled: bool,

    _has_banner: bool,
    banner: ?[]const u8,

    _has_accent_color: bool,
    accent_color: ?i32,

    _has_locale: bool,
    locale: []const u8,

    _has_verified: bool,
    verified: bool,

    _has_email: bool,
    email: ?[]const u8,

    _has_flags: bool,
    flags: i32,

    _has_premium_type: bool,
    premium_type: i32,

    _has_public_flags: bool,
    public_flags: i32,

    _has_avatar_decoration_data: bool,
    avatar_decoration_data: ?AvatarDecorationData,

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !User {
        return try modifiedJsonParseFromValue(User, allocator, source, options);
    }
};

pub const Guild = struct {
    pub const Unavailable = struct {
        id: []const u8,
        unavailable: bool,
    };
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

        _has_shard: bool,
        shard: Sharding,

        application: struct {
            id: Snowflake,
            flags: i32,
        },

        pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !Ready {
            return try modifiedJsonParseFromValue(Ready, allocator, source, options);
        }
    };
};
