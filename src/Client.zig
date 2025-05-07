const std = @import("std");
const websocket = @import("websocket");
const gateway = @import("gateway.zig");
const gateway_message = @import("gateway_message.zig");

const Cache = @import("./cache.zig").Cache;

const User = @import("./structures/User.zig");

const Client = @This();

pub const InitOptions = struct {
    allocator: std.mem.Allocator,
};

pub const Event = union(enum) {
    pub const DispatchType = enum {
        ready,
        message_create,
    };

    pub const Ready = struct {
        user: *User,
    };

    pub const MessageCreate = struct {};

    ready: Ready,
    message_create: MessageCreate,
};

pub const dispatch_event_map: std.StaticStringMap(Event.DispatchType) = .initComptime(.{
    .{ "READY", .ready },
    .{ "MESSAGE_CREATE", .message_create },
});

allocator: std.mem.Allocator,
maybe_gateway_client: ?gateway.Client,

user_cache: Cache(User),

pub fn init(options: InitOptions) !Client {
    return .{
        .allocator = options.allocator,
        .maybe_gateway_client = null,
        .user_cache = .init(options.allocator),
    };
}

pub fn deinit(self: *Client) void {
    if (self.maybe_gateway_client) |*gateway_client| {
        gateway_client.deinit();
    }
}

pub fn connected(self: *Client) bool {
    return self.maybe_gateway_client != null;
}

pub fn disconnect(self: *Client) !void {
    var gateway_client: *gateway.Client = &(self.maybe_gateway_client orelse return error.NotConnected);

    try gateway_client.disconnect();
    gateway_client.deinit();
    self.maybe_gateway_client = null;
}

pub fn connectAndLogin(self: *Client, token: []const u8, options: gateway.Options) !void {
    if (self.maybe_gateway_client != null) return error.Connected;

    self.maybe_gateway_client = try gateway.Client.init(self.allocator, token, options);
    try self.maybe_gateway_client.?.connectAndAuthenticate();
}

pub fn receive(self: *Client) !Event {
    const gateway_client: *gateway.Client = &(self.maybe_gateway_client orelse return error.NotConnected);

    while (true) {
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();

        const allocator = arena.allocator();

        switch (try gateway_client.readMessage(allocator)) {
            .dispatch_event => |dispatch_event| {
                const dispatch_event_type = dispatch_event_map.get(dispatch_event.name) orelse continue;

                switch (dispatch_event_type) {
                    .ready => {
                        const ready_data = try std.json.parseFromValueLeaky(
                            gateway_message.payload.Ready,
                            allocator,
                            dispatch_event.data_json,
                            .{
                                .allocate = .alloc_always,
                                .ignore_unknown_fields = true,
                            },
                        );

                        const user = try self.user_cache.patch(ready_data.user);

                        return .{
                            .ready = .{
                                .user = user,
                            },
                        };
                    },
                    .message_create => {
                        return .{
                            .message_create = .{},
                        };
                    },
                }
            },
            .hello, .invalid_session, .reconnect => {
                // TODO: handle
            },
            .close => |close_opcode| {
                switch (close_opcode) {
                    .rate_limited => return error.RateLimited,
                    .session_timed_out => return error.TimedOut,
                    .not_authenticated,
                    .authentication_failed,
                    .already_authenticated,
                    => return error.AuthenticationFailed,
                    .invalid_intents,
                    .disallowed_intents,
                    => return error.BadIntents,
                    .unknown_error,
                    .unknown_opcode,
                    .decode_error,
                    .invalid_sequence,
                    .invalid_shard,
                    .sharding_required,
                    .invalid_api_version,
                    => return error.UnexpectedClose,
                }
            },
        }
    }
}

pub fn receiveAndDispatch(self: *Client, handler: anytype) !void {
    const event = try self.receive();

    switch (event) {
        .ready => |ev| if (@hasDecl(@TypeOf(handler.*), "ready")) try handler.ready(ev),
        .message_create => |ev| if (@hasDecl(@TypeOf(handler.*), "messageCreate")) try handler.messageCreate(ev),
    }
}
