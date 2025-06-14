const std = @import("std");
const builtin = @import("builtin");
const websocket = @import("websocket");

const log = @import("log.zig").zeppelin;

const gateway_message = @import("gateway_message.zig");

pub const State = enum {
    established,
    received_hello,
    sent_identify,
    ready,
    disconnect,

    pub fn alive(self: State) bool {
        return switch (self) {
            .received_hello, .sent_identify, .ready => true,
            .established, .disconnect => false,
        };
    }
};

const IntentInt = i32;

pub const Intent = packed struct(IntentInt) {
    guilds: bool = false,
    guild_members: bool = false,
    guild_moderation: bool = false,
    guild_expressions: bool = false,
    guild_integrations: bool = false,
    guild_webhooks: bool = false,
    guild_invites: bool = false,
    guild_voice_states: bool = false,
    guild_presences: bool = false,
    guild_messages: bool = false,
    guild_message_reactions: bool = false,
    guild_message_typing: bool = false,
    direct_messages: bool = false,
    direct_message_reactions: bool = false,
    direct_message_typing: bool = false,
    message_content: bool = false,
    guild_scheduled_events: bool = false,
    _padding1: enum(u3) { unset } = .unset,
    auto_moderation_configuration: bool = false,
    auto_moderation_execution: bool = false,
    _padding2: enum(u2) { unset } = .unset,
    guild_message_polls: bool = false,
    direct_message_polls: bool = false,
    _padding3: enum(u6) { unset } = .unset,

    pub const all: Intent = .{
        .guilds = true,
        .guild_members = true,
        .guild_moderation = true,
        .guild_expressions = true,
        .guild_integrations = true,
        .guild_webhooks = true,
        .guild_invites = true,
        .guild_voice_states = true,
        .guild_presences = true,
        .guild_messages = true,
        .guild_message_reactions = true,
        .guild_message_typing = true,
        .direct_messages = true,
        .direct_message_reactions = true,
        .direct_message_typing = true,
        .message_content = true,
        .guild_scheduled_events = true,
        .auto_moderation_configuration = true,
        .auto_moderation_execution = true,
        .guild_message_polls = true,
        .direct_message_polls = true,
    };

    pub const unprivileged: Intent = blk: {
        var out = all;
        out.guild_members = false;
        out.guild_presences = false;
        out.message_content = false;
        break :blk out;
    };
};

pub const MessageRead = union(enum) {
    pub const DispatchEvent = struct {
        name: []const u8,
        data_json: std.json.Value,
    };

    pub const Hello = struct {
        heartbeat_interval: usize,
    };

    dispatch_event: DispatchEvent,
    reconnect: void,
    invalid_session: void,
    hello: Hello,
    close: ?gateway_message.opcode.Close,
};

pub const Config = struct {
    pub const Compression = enum {
        none,
        zlib,
        zstd,
    };
    compression: Compression = .none,
};

pub const Options = struct {
    intents: Intent = .{},
    host: []const u8 = "gateway.discord.gg",
    session_id: []const u8 = "",

    pub fn dupe(self: Options, allocator: std.mem.Allocator) !Options {
        const host = try allocator.dupe(u8, self.host);
        errdefer allocator.free(host);
        const session_id = try allocator.dupe(u8, self.session_id);
        errdefer allocator.free(session_id);

        return .{
            .intents = self.intents,
            .host = host,
            .session_id = session_id,
        };
    }
};

pub fn Client(config: Config) type {
    return struct {
        const ClientT = @This();

        const CompressionFifo = switch (config.compression) {
            .none => void,
            .zlib, .zstd => std.fifo.LinearFifo(u8, .Dynamic),
        };

        const DecompressorWindow = switch (config.compression) {
            .none, .zlib => void,
            .zstd => []u8,
        };

        const Decompressor = switch (config.compression) {
            .none => void,
            .zlib => std.compress.zlib.Decompressor(CompressionFifo.Reader),
            .zstd => std.compress.zstd.Decompressor(CompressionFifo.Reader),
        };

        const DataReader = switch (config.compression) {
            .none => std.io.FixedBufferStream([]u8).Reader,
            .zlib, .zstd => Decompressor.Reader,
        };

        allocator: std.mem.Allocator,
        websocket_client: websocket.Client,

        token_ephemeral: ?[]const u8,
        options: Options,

        compression_fifo: CompressionFifo,
        decompressor_window: DecompressorWindow,
        decompressor: Decompressor,

        heartbeat_reset: std.Thread.ResetEvent,
        heartbeat_thread: ?std.Thread,

        heartbeat_interval: ?usize,
        sequence_number: ?usize,
        was_last_heartbeat_acknowledged: bool,
        state: State,

        pub fn init(
            self: *ClientT,
            allocator: std.mem.Allocator,
            token_ephemeral: []const u8,
            options: Options,
        ) !void {
            var websocket_client = try websocket.Client.init(allocator, .{
                .host = options.host,
                .port = 443,
                .tls = true,
            });
            errdefer websocket_client.deinit();

            var headers_buffer: [1024]u8 = undefined;
            const headers = try std.fmt.bufPrint(&headers_buffer,
                \\Host: {s}
            , .{options.host});

            // var path_buffer: [128]u8 = undefined;
            // var path_array: std.ArrayListUnmanaged(u8) = .fromOwnedSlice(&path_buffer);

            // const path_writer = path_array.fixedWriter();
            // try path_writer.print("/?v=10&encoding=json", .{}); // todo: ETF encoding
            // switch (config.compression) {
            //     .none => {},
            //     .zlib => try path_writer.print("&compress=zlib-stream", .{}),
            //     .zstd => try path_writer.print("&compress=zstd-stream", .{}),
            // }

            const path = "/?v=10&encoding=json" ++ switch (config.compression) {
                .none => "",
                .zlib => "&compress=zlib-stream",
                .zstd => "&compress=zstd-stream",
            };

            log.info("Gateway connecting at wss://{s}{s}", .{ options.host, path });

            try websocket_client.handshake(path, .{
                .timeout_ms = 5000,
                .headers = headers,
            });

            self.* = .{
                .allocator = allocator,
                .websocket_client = websocket_client,

                .token_ephemeral = token_ephemeral,
                .options = options,

                .compression_fifo = undefined,
                .decompressor_window = undefined,
                .decompressor = undefined,

                .heartbeat_reset = .{},
                .heartbeat_thread = null,

                .heartbeat_interval = std.time.ms_per_s * 40,
                .sequence_number = null,
                .was_last_heartbeat_acknowledged = true,
                .state = .established,
            };

            self.compression_fifo = switch (config.compression) {
                .none => {},
                .zlib, .zstd => .init(allocator),
            };

            self.decompressor_window = switch (config.compression) {
                .none, .zlib => {},
                .zstd => try self.allocator.alloc(u8, std.compress.zstd.DecompressorOptions.default_window_buffer_len),
            };
            errdefer switch (config.compression) {
                .none, .zlib => {},
                .zstd => self.allocator.free(self.decompressor_window),
            };

            self.decompressor = switch (config.compression) {
                .none => {},
                .zlib => .init(self.compression_fifo.reader()),
                .zstd => .init(
                    self.compression_fifo.reader(),
                    .{ .window_buffer = self.decompressor_window },
                ),
            };
        }

        pub fn deinit(self: *ClientT) void {
            self.stopHeartbeat();
            self.websocket_client.deinit();
            switch (config.compression) {
                .none, .zlib => {},
                .zstd => self.allocator.free(self.decompressor_window),
            }
            switch (config.compression) {
                .none => {},
                .zlib, .zstd => self.compression_fifo.deinit(),
            }
        }

        pub fn disconnect(self: *ClientT) !void {
            self.stopHeartbeat();
            try self.websocket_client.close(.{});
        }

        pub fn stopHeartbeat(self: *ClientT) void {
            if (self.heartbeat_thread) |thread| {
                self.heartbeat_reset.set();
                thread.join();
                self.heartbeat_thread = null;
            }
        }

        pub fn connectAndAuthenticate(self: *ClientT) !?MessageRead {
            try self.websocket_client.readTimeout(0);

            while (true) {
                var arena: std.heap.ArenaAllocator = .init(self.allocator);
                defer arena.deinit();

                const allocator = arena.allocator();

                const message = try self.readMessage(allocator);
                switch (message) {
                    .dispatch_event => {},
                    .reconnect,
                    .invalid_session,
                    => return message,
                    .hello => |hello_details| {
                        self.heartbeat_interval = hello_details.heartbeat_interval;
                        self.heartbeat_thread = try std.Thread.spawn(.{}, heartbeatInterval, .{self});
                        self.state = .received_hello;

                        try self.sendIdentify(allocator);
                        break;
                    },
                    .close => return error.UnexpectedClose,
                }
            }
            return null;
        }

        pub fn readMessage(self: *ClientT, arena: std.mem.Allocator) !MessageRead {
            while (true) {
                const message = try self.websocket_client.read() orelse unreachable;
                defer self.websocket_client.done(message);

                switch (message.type) {
                    .text, .binary => {
                        var fbs = switch (config.compression) {
                            .none => std.io.fixedBufferStream(message.data),
                            .zlib, .zstd => {
                                try self.compression_fifo.write(message.data);
                            },
                        };

                        const data_reader = switch (config.compression) {
                            .none => fbs.reader(),
                            .zlib => self.decompressor.reader(),
                            .zstd => self.decompressor.reader(),
                        };

                        var json_reader: std.json.Reader(std.json.default_buffer_size, DataReader) = .init(arena, data_reader);

                        const event = try std.json.parseFromTokenSourceLeaky(gateway_message.Receive, arena, &json_reader, .{
                            .allocate = .alloc_always,
                            .ignore_unknown_fields = true,
                        });

                        const opcode = std.meta.intToEnum(gateway_message.opcode.Receive, event.op) catch {
                            return error.UnknownOpcode;
                        };

                        if (event.s) |new_sequence_number| {
                            self.sequence_number = @intCast(new_sequence_number);
                        }

                        switch (opcode) {
                            .dispatch => {
                                return .{ .dispatch_event = .{
                                    .name = event.t.?,
                                    .data_json = event.d.?,
                                } };
                            },
                            .heartbeat => {
                                try self.sendHeartbeat(arena);
                            },
                            .reconnect => {
                                return .reconnect;
                            },
                            .invalid_session => {
                                return .invalid_session;
                            },
                            .hello => {
                                const hello_payload = try std.json.parseFromValueLeaky(
                                    gateway_message.payload.Hello,
                                    arena,
                                    event.d orelse .null,
                                    .{
                                        .ignore_unknown_fields = true,
                                    },
                                );
                                log.debug("Got hello, heartbeat interval: {}", .{hello_payload.heartbeat_interval});
                                return .{ .hello = .{
                                    .heartbeat_interval = @intCast(hello_payload.heartbeat_interval),
                                } };
                            },
                            .heartbeat_acknowledge => {
                                self.was_last_heartbeat_acknowledged = true;
                                log.debug("Last heartbeat was acknowledged", .{});
                            },
                        }
                    },
                    .ping => {
                        try self.websocket_client.writeFrame(.pong, @constCast(message.data));
                    },
                    .close => {
                        if (message.data.len > 1) blk: {
                            const close_opcode_int = std.mem.readInt(u16, message.data[0..2], .big);

                            const close_opcode = std.meta.intToEnum(
                                gateway_message.opcode.Close,
                                close_opcode_int,
                            ) catch break :blk;

                            return .{ .close = close_opcode };
                        }

                        try self.websocket_client.close(.{});
                        return .{ .close = null };
                    },
                    .pong => {},
                }
            }
        }

        fn sendEvent(
            self: *ClientT,
            allocator: std.mem.Allocator,
            comptime opcode: gateway_message.opcode.Send,
            payload: opcode.Payload(),
        ) !void {
            const send_event: gateway_message.Send(opcode.Payload()) = .{
                .op = @intFromEnum(opcode),
                .d = payload,
            };

            const data = try std.json.stringifyAlloc(allocator, send_event, .{});
            defer allocator.free(data);

            try self.websocket_client.write(data);
        }

        fn sendIdentify(self: *ClientT, allocator: std.mem.Allocator) !void {
            const token = self.token_ephemeral orelse {
                log.err("Expected token to be available for identify", .{});
                return;
            };
            self.token_ephemeral = null;

            try self.sendEvent(allocator, .identify, .{
                .token = token,
                .properties = .{
                    .os = @tagName(builtin.os.tag),
                    .browser = "zeppelin",
                    .device = "zeppelin",
                },
                .intents = @bitCast(self.options.intents),
            });
        }

        fn sendHeartbeat(self: *ClientT, allocator: std.mem.Allocator) !void {
            try self.sendEvent(allocator, .heartbeat, self.sequence_number);
        }

        fn heartbeatInterval(self: *ClientT) !void {
            var prng = std.Random.DefaultPrng.init(@intCast(std.time.microTimestamp()));
            const interval: i64 = @intCast(self.heartbeat_interval.?);
            var wait_ms = prng.random().intRangeAtMost(i64, 0, interval);

            while (true) {
                defer wait_ms = interval;
                log.debug("Sending heartbeat in {}ms", .{wait_ms});
                if (self.heartbeat_reset.timedWait(@intCast(std.time.ns_per_ms * wait_ms))) {
                    log.warn("Heartbeats disconnected", .{});
                    break; // no more heartbeats, gateway disconnected
                } else |e| {
                    switch (e) {
                        error.Timeout => {
                            if (!self.state.alive()) continue;
                            var arena: std.heap.ArenaAllocator = .init(self.allocator);
                            defer arena.deinit();

                            if (!self.was_last_heartbeat_acknowledged) {
                                try self.websocket_client.close(.{});
                                break;
                            }

                            self.was_last_heartbeat_acknowledged = false;
                            try self.sendHeartbeat(arena.allocator());
                        },
                        else => return e,
                    }
                }
            }
        }
    };
}
