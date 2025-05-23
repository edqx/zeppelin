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
        // const allocator = message_create_event.arena;
        const message = message_create_event.message;

        if (self.own_user.id == message.author.id) return;

        if (!message.meta.queried(.member)) return;

        if (std.mem.eql(u8, message.content, "delete channel")) {
            try message.channel.delete();
        }
    }

    pub fn guildMemberAdd(self: *Handler, guild_member_add_event: zeppelin.Event.GuildMemberAdd) !void {
        _ = self;
        const guild_member = guild_member_add_event.guild_member;

        std.log.info("Member {s} joined!", .{guild_member.nick orelse guild_member.user.username});
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
