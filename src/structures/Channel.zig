const Snowflake = @import("../snowflake.zig").Snowflake;
const Client = @import("../Client.zig");

pub const Data = @import("../gateway_message.zig").Channel;

const Channel = @This();

context: *Client,
id: Snowflake,
received: bool,

pub fn deinit(self: *Channel) void {
    _ = self;
}

pub fn patch(self: *Channel, data: Data) !void {
    _ = self;
    _ = data;
}
