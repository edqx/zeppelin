const std = @import("std");

const api_root = "https://discord.com/api/v10";

pub const endpoints = struct {
    pub const create_message = api_root ++ "/channels/{[channel_id]}/messages";
    pub const create_dm = api_root ++ "/users/@me/channels";
};
