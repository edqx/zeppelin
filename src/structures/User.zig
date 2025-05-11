const std = @import("std");

const Snowflake = @import("../snowflake.zig").Snowflake;
const QueriedFields = @import("../queryable.zig").QueriedFields;
const Client = @import("../Client.zig");

pub const Data = @import("../gateway_message.zig").User;

const User = @This();

const AvatarDecorationData = struct {
    asset: []const u8,
    sku_id: Snowflake,
};

meta: QueriedFields(User, .{
    "username",               "discriminator", "global_name",
    "avatar",                 "bot",           "system",
    "mfa_enabled",            "banner",        "accent_color",
    "locale",                 "verified",      "email",
    "flags",                  "premium_type",  "public_flags",
    "avatar_decoration_data",
}) = .none,

context: *Client,
id: Snowflake,

username: []const u8 = "",
discriminator: []const u8 = "",
global_name: ?[]const u8 = null,
avatar: ?[]const u8 = null,
bot: bool = false,
system: bool = false,
mfa_enabled: bool = false,
banner: ?[]const u8 = null,
accent_color: ?i32 = null,
locale: []const u8 = "",
verified: bool = false,
email: ?[]const u8 = null,
flags: i32 = 0,
premium_type: i32 = 0,
public_flags: i32 = 0,
avatar_decoration_data: ?AvatarDecorationData = null,

pub fn deinit(self: *User) void {
    const allocator = self.context.allocator;

    allocator.free(self.username);
    allocator.free(self.discriminator);
}

pub fn patch(self: *User, data: Data) !void {
    if (self.meta.queried(.username)) self.context.allocator.free(self.username);
    self.meta.patch(.username, try self.context.allocator.dupe(u8, data.username));
    if (self.meta.queried(.discriminator)) self.context.allocator.free(self.discriminator);
    self.meta.patch(.discriminator, try self.context.allocator.dupe(u8, data.discriminator));

    self.meta.patchElective(.bot, data.bot);
    self.meta.patchElective(.system, data.system);
    self.meta.patchElective(.mfa_enabled, data.mfa_enabled);
    self.meta.patchElective(.banner, data.banner);
    self.meta.patchElective(.accent_color, data.accent_color);
    self.meta.patchElective(.locale, data.locale);
    self.meta.patchElective(.verified, data.verified);
    self.meta.patchElective(.email, data.email);
    self.meta.patchElective(.flags, data.flags);

    switch (data.avatar_decoration_data) {
        .not_given => {},
        .val => |maybe_avatar_decoration_data| self.meta.patch(
            .avatar_decoration_data,
            if (maybe_avatar_decoration_data) |avatar_decoration_data| .{
                .asset = avatar_decoration_data.asset,
                .sku_id = try Snowflake.resolve(avatar_decoration_data.sku_id),
            } else null,
        ),
    }
}
