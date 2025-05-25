const std = @import("std");

const api_root = "https://discord.com/api/v10";

pub const endpoints = struct {
    pub const get_user = api_root ++ "/users/{[user_id]}";
    pub const get_guild = api_root ++ "/guilds/{[guild_id]}";
    pub const get_guild_role = api_root ++ "/guilds/{[guild_id]}/roles/{[role_id]}";
    pub const get_channel = api_root ++ "/channels/{[channel_id]}";
    pub const get_channel_message = api_root ++ "/channels/{[channel_id]}/messages/{[message_id]}";

    pub const create_message = api_root ++ "/channels/{[channel_id]}/messages";
    pub const delete_message = api_root ++ "/channels/{[channel_id]}/messages/{[message_id]}";

    pub const create_dm = api_root ++ "/users/@me/channels";
    pub const delete_channel = api_root ++ "/channels/{[channel_id]}";

    pub const create_reaction = api_root ++ "/channels/{[channel_id]}/messages/{[message_id]}/reactions/{[emoji_id]}/@me";
};
