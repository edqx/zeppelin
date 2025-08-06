const std = @import("std");

const Snowflake = @import("../../snowflake.zig").Snowflake;
const QueriedFields = @import("../../queryable.zig").QueriedFields;
const Client = @import("../../Client.zig");

const MessageBuilder = @import("../../MessageBuilder.zig");

pub const Data = @import("../../gateway_message.zig").Interaction;

const Interaction = @This();

pub const Type = enum(i32) {
    ping,
    application_command,
    message_component,
    application_command_autocomplete,
    modal_submit,
};

pub const ResponseType = enum(i32) {
    pong,
    channel_message_with_source = 4,
    deferred_channel_message_with_source,
    deferred_update_message,
    update_message,
    application_command_autocomplete_result,
    modal,
    premium_required,
    launch_activity = 12,
};

meta: QueriedFields(Interaction, &.{}) = .none,

context: *Client,

id: Snowflake,
application_id: Snowflake = .nil,
type: Type = .ping,

pub fn deinit(self: *Interaction) void {
    _ = self;
}

pub fn patch(self: *Interaction, data: Data) !void {
    self.type = @enumFromInt(data.type);
}

pub fn fetchUpdate(self: *Interaction) !void {
    _ = try self.context.roles.fetch(self.guild.id, self.id);
}

pub fn fetchUpdateIfIncomplete(self: *Interaction) !void {
    if (self.meta.complete()) return;
    try self.fetchUpdate();
}

pub fn responseMessageWriter(self: Interaction, token: []const u8) !Client.ResponseWriter {
    return try self.context.interactionResponseMessageWriter(self.id, token);
}

pub fn createResponseMessage(self: Interaction, token: []const u8, message_builder: MessageBuilder) !void {
    try self.context.createInteractionResponseMessage(self.id, token, message_builder);
}
