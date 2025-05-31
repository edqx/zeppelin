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

        if (std.mem.eql(u8, message.content, "embed")) {
            var builder: zeppelin.MessageBuilder = .{ .allocator = allocator };

            {
                const writer = builder.contentWriter();
                try writer.print("Jesus is a descendent of Jesus", .{});
            }

            {
                const embed = try builder.embed();
                try embed.title("Philosophers", .{});
                try embed.description("Here are a list of philosophers", .{});

                embed.color(.{ .r = 255, .g = 255, .b = 0 });

                try embed.image(.{ .attachment = "barney.png" });

                const field1 = try embed.field();
                try field1.title("Who is Aristotle?", .{});
                try field1.body("Greek Philosopher", .{});

                const field2 = try embed.field();
                try field2.title("Who is Plato?", .{});
                try field2.body("Greek Philosopher", .{});

                const field3 = try embed.field();
                try field3.title("Who is Kant?", .{});
                try field3.body("German Philosopher", .{});

                try embed.footer("This is a footer", .{}, .{ .attachment = "barney.png" });
            }
            {
                const embed2 = try builder.embed();
                try embed2.title("Mark 9:24", .{});

                const writer = embed2.descriptionWriter();
                try writer.print("Immediately the boy's father {s}", .{"cried out"});
                try writer.print(" and said, \"I do believe; help my unbelief!\"", .{});
            }

            var message_writer = try message.channel.inner.guild_text.messageWriter();

            try message_writer.write(builder);

            try message_writer.beginAttachment("image/png", "barney.png");

            var file = try std.fs.cwd().openFile("barney.png", .{});
            defer file.close();

            var fifo: std.fifo.LinearFifo(u8, .{ .Static = 4096 }) = .init();

            try fifo.pump(file.reader(), message_writer.writer());

            try message_writer.end();

            _ = try message_writer.create();
        }
    }

    pub fn messageUpdate(self: *Handler, message_update_event: zeppelin.Event.MessageUpdate) !void {
        const message = message_update_event.message;
        _ = self;

        std.log.info("message update: '{s}'", .{message.content});
    }

    pub fn guildMemberAdd(self: *Handler, guild_member_add_event: zeppelin.Event.GuildMemberAdd) !void {
        _ = self;
        const guild_member = guild_member_add_event.guild_member;

        std.log.info("Member {s} joined!", .{guild_member.nick orelse guild_member.user.username});
    }

    pub fn guildMemberRemove(self: *Handler, guild_member_remove_event: zeppelin.Event.GuildMemberRemove) !void {
        _ = self;
        const guild_member = guild_member_remove_event.guild_member;

        std.log.info("Member {s} left!", .{guild_member.nick orelse guild_member.user.username});
    }

    pub fn guildMemberUpdate(self: *Handler, guild_member_update_event: zeppelin.Event.GuildMemberUpdate) !void {
        _ = self;
        const guild_member = guild_member_update_event.guild_member;
        std.log.info("Member '{s}' has {} roles", .{ guild_member.nick orelse guild_member.user.username, guild_member.roles.count() });
    }

    pub fn messageDelete(self: *Handler, message_delete_event: zeppelin.Event.MessageDelete) !void {
        _ = self;

        const allocator = message_delete_event.arena;
        const message = message_delete_event.message;

        if (!message.meta.queried(.content)) return;

        _ = try message.channel.inner.guild_text.createMessage(try .simple(allocator, "babe don't delete your message: '{s}'", .{message.content}));
    }
};

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
