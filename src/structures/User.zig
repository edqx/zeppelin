const std = @import("std");

const Snowflake = @import("../snowflake.zig").Snowflake;
const Queryable = @import("../queryable.zig").Queryable;
const Client = @import("../Client.zig");

pub const Data = @import("../gateway_message.zig").User;

const User = @This();

const AvatarDecorationData = struct {
    asset: []const u8,
    sku_id: Snowflake,
};

context: *Client,
id: Snowflake,
received: bool,

username: []const u8 = "",
discriminator: []const u8 = "",
global_name: ?[]const u8 = null,
avatar: ?[]const u8 = null,
bot: Queryable(bool) = .unknown,
system: Queryable(bool) = .unknown,
mfa_enabled: Queryable(bool) = .unknown,
banner: Queryable(?[]const u8) = .unknown,
accent_color: Queryable(?i32) = .unknown,
locale: Queryable([]const u8) = .unknown,
verified: Queryable(bool) = .unknown,
email: Queryable(?[]const u8) = .unknown,
flags: Queryable(i32) = .unknown,
premium_type: Queryable(i32) = .unknown,
public_flags: Queryable(i32) = .unknown,
avatar_decoration_data: Queryable(?AvatarDecorationData) = .unknown,

pub fn deinit(self: *User) void {
    self.context.allocator.free(self.username);
    self.context.allocator.free(self.discriminator);
}

pub fn patch(self: *User, data: Data) !void {
    self.context.allocator.free(self.username);
    self.context.allocator.free(self.discriminator);
    self.username = try self.context.allocator.dupe(u8, data.username);
    self.discriminator = try self.context.allocator.dupe(u8, data.discriminator);
    self.bot.patch(data.bot);
    self.system.patch(data.system);
    self.mfa_enabled.patch(data.mfa_enabled);
    self.banner.patch(data.banner);
    self.accent_color.patch(data.accent_color);
    self.locale.patch(data.locale);
    self.verified.patch(data.verified);
    self.email.patch(data.email);
    self.flags.patch(data.flags);
    self.premium_type.patch(data.premium_type);
    self.public_flags.patch(data.public_flags);
    if (data.avatar_decoration_data) |maybe_avatar_decoration_data| self.avatar_decoration_data = .{
        .known = if (maybe_avatar_decoration_data) |avatar_decoration_data| .{
            .asset = avatar_decoration_data.asset,
            .sku_id = try Snowflake.resolve(avatar_decoration_data.sku_id),
        } else null,
    };
}
