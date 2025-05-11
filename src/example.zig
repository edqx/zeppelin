const std = @import("std");
const builtin = @import("builtin");

const zeppelin = @import("zeppelin");

const use_gpa = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;

const Handler = struct {
    client: *zeppelin.Client,

    pub fn ready(self: *Handler, ready_event: zeppelin.Event.Ready) !void {
        const cached_user = self.client.global_cache.users.resolve(ready_event.user.id).?;

        if (cached_user.meta.complete()) {}

        std.log.info("Logged in as {s}", .{cached_user.username});
    }

    pub fn messageCreate(self: *Handler, message_create_event: zeppelin.Event.MessageCreate) !void {
        _ = self;

        const message = message_create_event.message;

        std.log.info("'{s}' from {s} in {?s}", .{
            message.content,
            message.author.username,
            message.channel.inner.guild_text.name,
        });
    }
};

pub fn main() !void {
    var gpa = if (use_gpa) std.heap.GeneralPurposeAllocator(.{}){} else {};
    defer if (use_gpa) std.debug.assert(gpa.deinit() == .ok);

    const allocator = if (use_gpa) gpa.allocator() else std.heap.c_allocator;

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const token = env_map.get("ZEPPELIN_TOKEN") orelse @panic("Missing environment variable ZEPPELIN_TOKEN");
    var client: zeppelin.Client = try .init(.{
        .allocator = allocator,
    });
    defer client.deinit();

    try client.connectAndLogin(token, .{
        .intents = .all,
    });

    var handler: Handler = .{ .client = &client };
    _ = &handler;

    var event_pool: zeppelin.EventPool(Handler) = .{
        .client = &client,
        .allocator = allocator,
        .handler = &handler,
    };
    defer event_pool.deinit();

    try event_pool.start();
}
