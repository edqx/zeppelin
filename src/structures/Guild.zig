const std = @import("std");

const Snowflake = @import("../snowflake.zig").Snowflake;
const QueriedFields = @import("../queryable.zig").QueriedFields;
const Client = @import("../Client.zig");

const Channel = @import("Channel.zig");

const gateway_message = @import("../gateway_message.zig");

pub const Data = union(enum) {
    unavailable: gateway_message.Guild.Unavailable,
    available: struct {
        base: gateway_message.Guild,
        channels: ?[]gateway_message.Channel,
    },
};

const Guild = @This();

meta: QueriedFields(Guild, &.{
    "available", "name", "channels",
}) = .none,

context: *Client,
id: Snowflake,

available: bool = false,
name: []const u8 = "",
channels: []*Channel = &.{},

pub fn deinit(self: *Guild) void {
    const allocator = self.context.allocator;

    allocator.free(self.name);
    allocator.free(self.channels);
}

pub fn patch(self: *Guild, data: Data) !void {
    const allocator = self.context.allocator;

    self.available = data == .available;

    switch (data) {
        .available => |inner_data| {
            allocator.free(self.name);
            self.name = try allocator.dupe(u8, inner_data.base.name);

            if (inner_data.channels) |channnels_data| {
                var channel_references: std.ArrayListUnmanaged(*Channel) = try .initCapacity(allocator, channnels_data.len);
                defer channel_references.deinit(allocator);

                for (channnels_data) |channel_data| {
                    var modified_data = channel_data;

                    modified_data.guild_id = .{ .val = inner_data.base.id }; // guild.channels don't have the guild id with them

                    channel_references.appendAssumeCapacity(
                        try self.context.global_cache.channels.patch(self.context, try .resolve(modified_data.id), modified_data),
                    );
                }

                self.meta.patch(.channels, try channel_references.toOwnedSlice(allocator));
            }
        },
        .unavailable => {
            self.meta = .none;
            self.available = false;
        },
    }
}
