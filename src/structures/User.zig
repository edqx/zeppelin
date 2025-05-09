const std = @import("std");

const Snowflake = @import("../snowflake.zig").Snowflake;
const Queryable = @import("../queryable.zig").Queryable;
const GlobalCache = @import("../Client.zig").GlobalCache;

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

pub fn init(self: *User, cache: *GlobalCache, gpa: std.mem.Allocator, data: Data) !void {
    self.id = try .resolve(data.id);
    self.username = "";
    self.discriminator = "";
    self.bot = .unknown;
    self.system = .unknown;
    self.mfa_enabled = .unknown;
    self.banner = .unknown;
    self.accent_color = .unknown;
    self.locale = .unknown;
    self.verified = .unknown;
    self.email = .unknown;
    self.flags = .unknown;
    self.premium_type = .unknown;
    self.public_flags = .unknown;
    self.avatar_decoration_data = .unknown;
    try self.patch(cache, gpa, data);
}

pub fn deinit(self: *User, gpa: std.mem.Allocator) void {
    gpa.free(self.username);
    gpa.free(self.discriminator);
}

pub fn patch(self: *User, cache: *GlobalCache, gpa: std.mem.Allocator, data: Data) !void {
    _ = cache;

    gpa.free(self.username);
    gpa.free(self.discriminator);
    self.username = try gpa.dupe(u8, data.username);
    self.discriminator = try gpa.dupe(u8, data.discriminator);
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
