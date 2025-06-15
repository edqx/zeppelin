const std = @import("std");
const builtin = @import("builtin");

const zeppelin = @import("zeppelin");

const use_gpa = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;

const Handler = struct {
    client: *zeppelin.Client,

    own_user: *zeppelin.User,

    pub fn ready(self: *Handler, ready_event: zeppelin.Event.Ready) !void {
        self.own_user = ready_event.user;
        std.log.info("Logged in as {s}", .{self.own_user.username});
    }

    pub fn userUpdate(self: *Handler, user_update_event: zeppelin.Event.UserUpdate) !void {
        _ = self;
        std.log.info("User new name: {s}", .{user_update_event.user.username});
    }

    pub fn messageCreate(self: *Handler, message_create_event: zeppelin.Event.MessageCreate) !void {
        const allocator = message_create_event.arena;
        const message = message_create_event.message;

        if (self.own_user.id == message.author.id) return;

        if (!message.meta.queried(.member)) return;

        if (std.mem.startsWith(u8, message.content, "!!type")) {
            const thread = try message.channel.anyText().startThreadWithOptions(.{
                .type = .public,
                .name = "hi this is a thread",
                .auto_archive_after = .@"1h",
            });

            _ = try thread.anyText().createMessage(try .simple(allocator, "hey barney", .{}));
        }
    }

    pub fn interactionCreate(self: *Handler, interaction_create_event: zeppelin.Event.InteractionCreate) !void {
        const allocator = interaction_create_event.arena;

        try self.client.createInteractionResponse(interaction_create_event.interaction_id, interaction_create_event.interaction_token, try .simple(allocator, "Pong!", .{}));

        std.log.info("Interaction created", .{});
    }
};

pub fn setup(allocator: std.mem.Allocator, client: *zeppelin.Client) !void {
    var command: zeppelin.ApplicationCommandBuilder = .init(allocator, .chat_input);
    defer command.deinit();

    try command.name("ping");
    try command.description("Ping the bot and get response times in milliseconds", .{});

    try client.bulkOverwriteGlobalApplicationCommands(.from(1227783493967413358), &.{command});
}

pub fn main() !void {
    var gpa = if (use_gpa) std.heap.GeneralPurposeAllocator(.{}){} else {};
    defer if (use_gpa) std.debug.assert(gpa.deinit() == .ok);

    const allocator = if (use_gpa) gpa.allocator() else std.heap.c_allocator;

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const token = env_map.get("ZEPPELIN_TOKEN") orelse @panic("Missing environment variable ZEPPELIN_TOKEN");
    var client: zeppelin.Client = undefined;
    try client.init(.{
        .allocator = allocator,
        .authentication = .{ .token = token },
    });
    defer client.deinit();

    try client.connectAndLogin(.{
        .intents = .all,
    });

    // try setup(allocator, &client);

    var handler: Handler = .{ .client = &client, .own_user = undefined };
    _ = &handler;

    var event_pool: zeppelin.EventPool(Handler) = undefined;
    defer event_pool.deinit();

    try event_pool.init(allocator, &client, &handler);
    try event_pool.start();
}
