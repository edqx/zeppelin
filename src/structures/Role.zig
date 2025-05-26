const std = @import("std");

const Snowflake = @import("../snowflake.zig").Snowflake;
const QueriedFields = @import("../queryable.zig").QueriedFields;
const Client = @import("../Client.zig");

const Pool = @import("../cache.zig").Pool;

const Mention = @import("../MessageBuilder.zig").Mention;
const Permissions = @import("../permissions.zig").Permissions;

const Guild = @import("Guild.zig");

pub const Data = @import("../gateway_message.zig").Role;

const Role = @This();

pub const Flags = packed struct(i32) {
    in_prompt: bool,
    _packed1: enum(u31) { unset } = .unset,
};

meta: QueriedFields(Role, &.{ "guild", "name", "permissions", "mentionable" }) = .none,

context: *Client,
id: Snowflake,

guild: *Guild = undefined,

name: []const u8 = "",
permissions: Permissions = .{},
mentionable: bool = false,

pub fn deinit(self: *Role) void {
    const allocator = self.context.allocator;
    allocator.free(self.name);
}

pub fn patch(self: *Role, data: Data) !void {
    const allocator = self.context.allocator;

    allocator.free(self.name);
    self.meta.patch(.name, try allocator.dupe(u8, data.name));

    const permission_integer = try std.fmt.parseInt(Permissions.Int, data.permissions, 10);
    self.meta.patch(.permissions, @bitCast(permission_integer));

    self.meta.patch(.mentionable, data.mentionable);
}

pub fn mention(self: *Role) !Mention {
    if (!self.mentionable) return error.NotMentionable;
    return .{ .role = self.id };
}
