const std = @import("std");

const Snowflake = @import("../../snowflake.zig").Snowflake;
const QueriedFields = @import("../../queryable.zig").QueriedFields;
const Client = @import("../../Client.zig");

const MessageBuilder = @import("../../MessageBuilder.zig");
const CommandType = @import("../../ApplicationCommandBuilder.zig").Type;

pub const Data = @import("../../gateway_message.zig").Interaction;

const Interaction = @This();

pub const Type = enum(i32) {
    ping,
    application_command,
    message_component,
    application_command_autocomplete,
    modal_submit,
};

pub const ComponentType = enum(i32) {
    action_row,
    button,
    string_select,
    text_input,
    user_select,
    role_select,
    mentionable_select,
    channel_select,
    section,
    text_display,
    thumbnail,
    media_gallery,
    file,
    separator,
    container,
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

pub const Command = struct {
    id: Snowflake,
    name: []const u8,
    type: CommandType,
    // todo: options, resolved
};

pub const Component = struct {
    custom_id: []const u8,
    component_type: ComponentType,
    // todo: values, resolved
};

pub const ModalSubmit = struct {
    custom_id: []const u8,
    components: []Component,
};

pub const Inner = union(enum) {
    command: Command,
    component: Component,
    modal_submit: ModalSubmit,
};

meta: QueriedFields(Interaction, &.{"inner"}) = .none,

context: *Client,

id: Snowflake,
application_id: Snowflake = .nil,
type: Type = .ping,

inner: Inner = undefined,

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

pub fn createResponseMessage(self: Interaction, token: []const u8, message_builder: MessageBuilder) !void {
    try self.context.createInteractionResponseMessage(self.id, token, message_builder);
}
