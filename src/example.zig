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

    pub fn messageCreate(self: *Handler, message_create_event: zeppelin.Event.MessageCreate) !void {
        const allocator = self.client.allocator;
        const message = message_create_event.message;

        if (self.own_user.id == message.author.id) return;

        if (!message.meta.queried(.member)) return;

        const text_channel = &message.channel.inner.guild_text;

        if (std.mem.eql(u8, message.content, "!ping")) {
            _ = try text_channel.createMessage(try .simple(allocator, "Pong!", .{}));
        }

        if (std.mem.eql(u8, message.content, "!explode-channel")) {
            var builder: zeppelin.MessageBuilder = .{ .allocator = allocator };
            defer builder.deinit();

            try builder.writer().print("Hello {}!", .{message.author.mention()});

            _ = try text_channel.createMessage(builder);
        }

        if (std.mem.eql(u8, message.content, "!hello-barney")) {
            _ = try message.channel.inner.guild_text.createMessage(blk: {
                var builder: zeppelin.MessageBuilder = .{ .allocator = allocator };
                errdefer builder.deinit();

                try builder.writer().print("Hello {}!", .{message.author.mention()});

                break :blk builder;
            });
        }

        if (std.mem.eql(u8, message.content, "!send-me-an-image")) {
            var message_writer = try text_channel.messageWriter();
            defer message_writer.deinit();

            try message_writer.write(try .simple(allocator, "Here's a message, .{}", .{message.author.mention()}));

            try message_writer.beginAttachment("image/jpg", "michael.jpg");

            {
                var file = try std.fs.cwd().openFile("michael.jpg", .{});
                defer file.close();

                var fifo: std.fifo.LinearFifo(u8, .{ .Static = 4096 }) = .init();
                defer fifo.deinit();

                try fifo.pump(file.reader(), message_writer.writer());
            }

            try message_writer.end();

            const created_message = try message_writer.create();
            std.log.info("message created with id {}", .{created_message.id});
        }
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
        .authentication = .{ .token = token },
    });
    defer client.deinit();

    try client.connectAndLogin(.{
        .intents = .all,
    });

    var handler: Handler = .{ .client = &client, .own_user = undefined };
    _ = &handler;

    var event_pool: zeppelin.EventPool(Handler) = .{
        .client = &client,
        .allocator = allocator,
        .handler = &handler,
    };
    defer event_pool.deinit();

    try event_pool.start();
}
