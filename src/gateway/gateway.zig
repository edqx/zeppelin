const std = @import("std");
const builtin = @import("builtin");
const websocket = @import("websocket");

const log = @import("../log.zig").zeppelin;

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
    hello: Hello,
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

    pub fn free(self: Options, allocator: std.mem.Allocator) void {
        allocator.free(self.host);
        allocator.free(self.session_id);
    }

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

pub const CloseOpcode = gateway_message.opcode.Close;

pub const InitError = std.mem.Allocator.Error || error { GatewayHandshakeFailed };
pub const AuthError = error { GatewayInvalidState };
pub const ReceiveError = error { GatewayClosed, GatewayReadFailed, GatewayJsonParseFailed, GatewayInvalidSession, GatewayReconnect, GatewayUnknownOpcode };
pub const SendError = error { GatewayHeartbeatFailed, GatewayJsonWriteFailed, GatewaySendFailed, GatewayWriteFailed };

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
        
        websocket_error: ?anyerror = null,

        pub fn init(
            self: *ClientT,
            allocator: std.mem.Allocator,
            token_ephemeral: []const u8,
            options: Options,
        ) InitError!void {
            const duped_options = try options.dupe(allocator);
            errdefer duped_options.free(allocator);
        
            var websocket_client = websocket.Client.init(allocator, .{
                .host = duped_options.host,
                .port = 443,
                .tls = true,
                .max_size = 65536 * 4,
            }) catch return error.GatewayHandshakeFailed;
            errdefer websocket_client.deinit();

            var headers_buffer: [1024]u8 = undefined;
            const headers = std.fmt.bufPrint(&headers_buffer,
                \\Host: {s}
            , .{duped_options.host}) catch unreachable;

            // var path_buffer: [128]u8 = undefined;
            // var path_array: std.ArrayListUnmanaged(u8) = .fromOwnedSlice(&path_buffer);

            // const path_writer = path_array.fixedWriter();
            // path_writer.print("/?v=10&encoding=json", .{}) catch unreachable; // todo: ETF encoding
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

            log.info("Gateway connecting at wss://{s}{s}", .{ duped_options.host, path });

            websocket_client.handshake(path, .{
                .timeout_ms = 5000,
                .headers = headers,
            }) catch return error.GatewayHandshakeFailed;

            self.* = .{
                .allocator = allocator,
                .websocket_client = websocket_client,

                .token_ephemeral = token_ephemeral,
                .options = duped_options,

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
            // this is duped in `init`
            self.options.free(self.allocator);
        }

        pub fn disconnect(self: *ClientT) !void {
            self.stopHeartbeat();
            self.websocket_client.close(.{}) catch return error.GatewaySendFailed;
        }

        pub fn stopHeartbeat(self: *ClientT) void {
            if (self.heartbeat_thread) |thread| {
                self.heartbeat_reset.set();
                thread.join();
                self.heartbeat_thread = null;
            }
        }

        // user of this gateway should wait for a 'ready' event
        pub fn connectAndAuthenticate(self: *ClientT, close_opcode: *CloseOpcode) (ReceiveError || SendError || AuthError)!void {
            // try self.websocket_client.readTimeout(0);

            var arena: std.heap.ArenaAllocator = .init(self.allocator);
            defer arena.deinit();

            const allocator = arena.allocator();

            // let's wait for a 'hello' response from the server
            const hello = try self.receiveMessage(allocator, close_opcode);
            switch (hello) {
                // we should not be receiving these events. the server is yet to greet us
                // and we are yet to identify
                .dispatch_event => return error.GatewayInvalidState,
                .hello => |hello_details| {
                    self.heartbeat_interval = hello_details.heartbeat_interval;
                    self.heartbeat_thread = std.Thread.spawn(.{}, heartbeatInterval, .{self}) catch return error.GatewayHeartbeatFailed;
                    self.state = .received_hello;

                    try self.sendIdentify();
                    return;
                },
            }
        }

        /// Filters out 'heartbeat' messages, returning the next 'interesting' one
        pub fn receiveMessage(self: *ClientT, arena: std.mem.Allocator, close_opcode: *CloseOpcode) (ReceiveError || SendError)!MessageRead {
            while (true) {
                const message = self.websocket_client.read() catch |e| {
                    self.websocket_error = e;
                    return error.GatewayReadFailed;
                } orelse unreachable;
                defer self.websocket_client.done(message);

                switch (message.type) {
                    .text, .binary => {
                        var fbs = switch (config.compression) {
                            .none => std.Io.Reader.fixed(message.data),
                            .zlib, .zstd => {
                                try self.compression_fifo.write(message.data);
                            },
                        };

                        const data_reader = switch (config.compression) {
                            .none => &fbs,
                            .zlib => self.decompressor.reader(),
                            .zstd => self.decompressor.reader(),
                        };

                        var json_reader: std.json.Reader = .init(arena, data_reader);

                        const event = std.json.parseFromTokenSourceLeaky(gateway_message.Receive, arena, &json_reader, .{
                            .allocate = .alloc_always,
                            .ignore_unknown_fields = true,
                        }) catch return error.GatewayJsonParseFailed;

                        const opcode = std.meta.intToEnum(gateway_message.opcode.Receive, event.op) catch {
                            return error.GatewayUnknownOpcode;
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
                                try self.sendHeartbeat();
                            },
                            .reconnect => {
                                return error.GatewayReconnect;
                            },
                            .invalid_session => {
                                return error.GatewayInvalidSession;
                            },
                            .hello => {
                                const hello_payload = std.json.parseFromValueLeaky(
                                    gateway_message.payload.Hello,
                                    arena,
                                    event.d orelse .null,
                                    .{
                                        .ignore_unknown_fields = true,
                                    },
                                ) catch return error.GatewayJsonParseFailed;

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
                        self.websocket_client.writeFrame(.pong, @constCast(message.data)) catch |e| {
                            self.websocket_error = e;
                            return error.GatewayWriteFailed;
                        };
                    },
                    .close => {
                        self.websocket_client.close(.{}) catch |e| {
                            self.websocket_error = e;
                            return error.GatewayWriteFailed;
                        };

                        // doesn't always contain a close code
                        if (message.data.len > 1) {
                            const close_opcode_int = std.mem.readInt(u16, message.data[0..2], .big);
                            close_opcode.* = std.meta.intToEnum(CloseOpcode, close_opcode_int) catch .none;
                            return error.GatewayClosed;
                        } else {
                            close_opcode.* = .none;
                        }

                        return error.GatewayClosed;
                    },
                    .pong => {},
                }
            }
        }

        fn sendEvent(
            self: *ClientT,
            comptime opcode: gateway_message.opcode.Send,
            payload: opcode.Payload(),
        ) SendError!void {
            const temp_allocator = self.allocator;
        
            const send_event: gateway_message.Send(opcode.Payload()) = .{
                .op = @intFromEnum(opcode),
                .d = payload,
            };

            // TODO: re-use buffers to avoid allocating every event. luckily sending on the gateway is not very
            // common
            const data = std.json.Stringify.valueAlloc(temp_allocator, send_event, .{}) catch return error.GatewayJsonWriteFailed;
            defer temp_allocator.free(data);

            self.websocket_client.write(data) catch return error.GatewaySendFailed;
        }

        fn sendIdentify(self: *ClientT) SendError!void {
            const token = self.token_ephemeral orelse {
                log.err("Expected token to be available for identify", .{});
                return;
            };
            self.token_ephemeral = null;

            try self.sendEvent(.identify, .{
                .token = token,
                .properties = .{
                    .os = @tagName(builtin.os.tag),
                    .browser = "zeppelin",
                    .device = "zeppelin",
                },
                .intents = @bitCast(self.options.intents),
            });
        }

        fn sendHeartbeat(self: *ClientT) SendError!void {
            try self.sendEvent(.heartbeat, self.sequence_number);
        }
        
        pub fn sendVoiceStateUpdate(self: *ClientT, update: gateway_message.payload.SendVoiceStateUpdate) SendError!void {
            try self.sendEvent(.voice_state_update, update);
        }

        fn heartbeatInterval(self: *ClientT) SendError!void {
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
                            if (!self.was_last_heartbeat_acknowledged) {
                                try self.disconnect();
                                break;
                            }

                            self.was_last_heartbeat_acknowledged = false;
                            try self.sendHeartbeat();
                        },
                    }
                }
            }
        }
    };
}
