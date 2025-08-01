const std = @import("std");

const api_root = "https://discord.com/api/v10";

pub const endpoints = struct {
    pub const get_user = api_root ++ "/users/{[user_id]f}";
    pub const get_guild = api_root ++ "/guilds/{[guild_id]f}";
    pub const get_guild_role = api_root ++ "/guilds/{[guild_id]f}/roles/{[role_id]f}";
    pub const get_channel = api_root ++ "/channels/{[channel_id]f}";
    pub const get_channel_message = api_root ++ "/channels/{[channel_id]f}/messages/{[message_id]f}";

    pub const trigger_typing_indicator = api_root ++ "/channels/{[channel_id]f}/typing";
    pub const create_message = api_root ++ "/channels/{[channel_id]f}/messages";
    pub const delete_message = api_root ++ "/channels/{[channel_id]f}/messages/{[message_id]f}";

    pub const create_dm = api_root ++ "/users/@me/channels";
    pub const delete_channel = api_root ++ "/channels/{[channel_id]f}";
    pub const start_thread_from_message = api_root ++ "/channels/{[channel_id]f}/messages/{[message_id]f}/threads";
    pub const start_thread_without_message = api_root ++ "/channels/{[channel_id]f}/threads";

    pub const create_reaction = api_root ++ "/channels/{[channel_id]f}/messages/{[message_id]f}/reactions/{[emoji_id]f}/@me";

    pub const bulk_overwrite_global_application_commands = api_root ++ "/applications/{[application_id]f}/commands";

    pub const create_interaction_response = api_root ++ "/interactions/{[interaction_id]f}/{[interaction_token]s}/callback";
};
