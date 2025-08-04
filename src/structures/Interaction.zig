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
