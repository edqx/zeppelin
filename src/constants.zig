const std = @import("std");

pub const endpoints = struct {
    pub const create_message = "https://discord.com/api/v10/channels/{[channel_id]}/messages";
};
