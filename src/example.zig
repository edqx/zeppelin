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
            try message.createReaction(.{ .unicode = "❤️" });
            _ = try message.createReplyMessage(try .simple(allocator, "Your message was created at {}", .{message.created_at}), .{});
        }
    }

    pub fn interactionCreate(self: *Handler, ev: zeppelin.Event.InteractionCreate) !void {
        _ = self;

        try ev.interaction.createResponseMessage(ev.token, try .simple(ev.arena, "Pong!", .{}));
    }
};

pub fn setup(allocator: std.mem.Allocator, client: *zeppelin.Client) !void {
    var command: zeppelin.ApplicationCommandBuilder = .{
        .type = .chat_input,
        .name = "barney",
        .description = try .fromSlice("This is a barney commany"),
    };
    defer command.deinit(allocator);

    var hug_sub_command = try command.addOption(allocator, .sub_command, .{
        .name = "hug",
        .description = try .fromSlice("hug barney"),
    });

    _ = try hug_sub_command.addOption(allocator, .integer, .{
        .option = .{
            .name = "love",
            .description = try .fromSlice("how much love to use when hugging barney"),
            .required = true,
        },
        .min = 0,
        .max = 10,
    });

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
