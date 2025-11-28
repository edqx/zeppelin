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
        const allocator = message_create_event.arena;
        const message = message_create_event.message;

        if (self.own_user.id == message.author.id) return;

        if (!message.meta.queried(.member)) return;

        if (std.mem.eql(u8, message.content, "summon barney")) {
            var message_builder: zeppelin.MessageBuilder = .init(allocator);
            defer message_builder.deinit();

            const action_row = try message_builder.addActionRow();
            const button = try action_row.layout.addButton();

            button.style = .success;
            button.custom_id = "kiss";
            try button.label.writer.print("Kiss Barney", .{});

            try message_builder.content.writer.print("Wooooff!", .{});

            _ = try message.createReplyMessage(message_builder, .{});
        }
    }

    pub fn interactionCreate(self: *Handler, interaction_create_event: zeppelin.Event.InteractionCreate) !void {
        const allocator = interaction_create_event.arena;
        const interaction = interaction_create_event.interaction;

        _ = self;

        switch (interaction.inner) {
            .component => |component_data| {
                if (std.mem.eql(u8, component_data.custom_id, "kiss")) {
                    _ = try interaction.createResponseMessage(
                        interaction_create_event.token,
                        try .simple(allocator, "\\*dodges*", .{}),
                    );
                }
            },
            else => {},
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

    var event_pool: zeppelin.EventPool(Handler) = undefined;
    defer event_pool.deinit();

    try event_pool.init(allocator, &client, &handler);
    try event_pool.start();
}
