const std = @import("std");
const Snowflake = @import("../snowflake.zig").Snowflake;
const Queryable = @import("../queryable.zig").Queryable;

pub const Data = @import("../gateway_message.zig").User;

const User = @This();

const AvatarDecorationData = struct {
    asset: []const u8,
    sku_id: Snowflake,
};

id: Snowflake,

username: []const u8,
discriminator: []const u8,
global_name: ?[]const u8,
avatar: ?[]const u8,
bot: Queryable(bool),
system: Queryable(bool),
mfa_enabled: Queryable(bool),
banner: Queryable(?[]const u8),
accent_color: Queryable(?i32),
locale: Queryable([]const u8),
verified: Queryable(bool),
email: Queryable(?[]const u8),
flags: Queryable(i32),
premium_type: Queryable(i32),
public_flags: Queryable(i32),
avatar_decoration_data: Queryable(?AvatarDecorationData),

pub fn init(self: *User, gpa: std.mem.Allocator, data: Data) !void {
    self.id = try .resolve(data.id);
    self.username = try gpa.dupe(u8, data.username);
    self.discriminator = try gpa.dupe(u8, data.discriminator);
    self.bot = if (data._has_bot) .{ .known = data.bot } else .unknown;
    self.system = if (data._has_system) .{ .known = data.system } else .unknown;
    self.mfa_enabled = if (data._has_mfa_enabled) .{ .known = data.mfa_enabled } else .unknown;
    self.banner = if (data._has_banner) .{ .known = data.banner } else .unknown;
    self.accent_color = if (data._has_accent_color) .{ .known = data.accent_color } else .unknown;
    self.locale = if (data._has_locale) .{ .known = data.locale } else .unknown;
    self.verified = if (data._has_verified) .{ .known = data.verified } else .unknown;
    self.email = if (data._has_email) .{ .known = data.email } else .unknown;
    self.flags = if (data._has_flags) .{ .known = data.flags } else .unknown;
    self.premium_type = if (data._has_premium_type) .{ .known = data.premium_type } else .unknown;
    self.public_flags = if (data._has_public_flags) .{ .known = data.public_flags } else .unknown;
    self.avatar_decoration_data = if (data._has_avatar_decoration_data) .{
        .known = if (data.avatar_decoration_data) |avatar_decoration_data| .{
            .asset = avatar_decoration_data.asset,
            .sku_id = try Snowflake.resolve(avatar_decoration_data.sku_id),
        } else null,
    } else .unknown;
}

pub fn patch(self: *User, gpa: std.mem.Allocator, data: Data) !void {
    gpa.free(self.username);
    gpa.free(self.discriminator);
    self.username = try gpa.dupe(u8, data.username);
    self.discriminator = try gpa.dupe(u8, data.discriminator);
    if (data._has_bot) self.bot = .{ .known = data.bot };
    if (data._has_system) self.system = .{ .known = data.system };
    if (data._has_mfa_enabled) self.mfa_enabled = .{ .known = data.mfa_enabled };
    if (data._has_banner) self.banner = .{ .known = data.banner };
    if (data._has_accent_color) self.accent_color = .{ .known = data.accent_color };
    if (data._has_locale) self.locale = .{ .known = data.locale };
    if (data._has_verified) self.verified = .{ .known = data.verified };
    if (data._has_email) self.email = .{ .known = data.email };
    if (data._has_flags) self.flags = .{ .known = data.flags };
    if (data._has_premium_type) self.premium_type = .{ .known = data.premium_type };
    if (data._has_public_flags) self.public_flags = .{ .known = data.public_flags };
    if (data._has_avatar_decoration_data) self.avatar_decoration_data = .{
        .known = if (data.avatar_decoration_data) |avatar_decoration_data| .{
            .asset = avatar_decoration_data.asset,
            .sku_id = try Snowflake.resolve(avatar_decoration_data.sku_id),
        } else null,
    };
}
