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

        pub fn Payload(comptime self: Send) type {
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

pub const event = struct {
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

        pub const Sharding = struct {
            shard_id: i32,
            num_shards: i32,
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
};
