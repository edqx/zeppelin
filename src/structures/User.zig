const std = @import("std");

const Snowflake = @import("../snowflake.zig").Snowflake;
const QueriedFields = @import("../queryable.zig").QueriedFields;
const Client = @import("../Client.zig");

const Mention = @import("../MessageBuilder.zig").Mention;

const Channel = @import("Channel.zig");

pub const Data = @import("../gateway_message.zig").User;

const User = @This();

const AvatarDecorationData = struct {
    asset: []const u8,
    sku_id: Snowflake,
};

meta: QueriedFields(User, &.{
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

    if (self.global_name) |global_name| allocator.free(global_name);
}

pub fn patch(self: *User, data: Data) !void {
    const allocator = self.context.allocator;

    allocator.free(self.username);
    self.meta.patch(.username, try allocator.dupe(u8, data.username));
    allocator.free(self.discriminator);
    self.meta.patch(.discriminator, try allocator.dupe(u8, data.discriminator));

    if (data.global_name) |data_global_name| {
        if (self.global_name) |global_name| allocator.free(global_name);

        self.meta.patch(.global_name, try allocator.dupe(u8, data_global_name));
    }

    self.meta.patchElective(.bot, data.bot);
    self.meta.patchElective(.system, data.system);
    self.meta.patchElective(.mfa_enabled, data.mfa_enabled);
    self.meta.patchElective(.banner, data.banner);
    self.meta.patchElective(.accent_color, data.accent_color);

    switch (data.locale) {
        .not_given => {},
        .val => |locale| {
            allocator.free(self.locale);
            self.meta.patch(.locale, try allocator.dupe(u8, locale));
        },
    }

    self.meta.patchElective(.locale, data.locale);
    self.meta.patchElective(.verified, data.verified);

    switch (data.email) {
        .not_given => {},
        .val => |maybe_email| {
            if (self.email) |email| allocator.free(email);

            self.meta.patch(.email, if (maybe_email) |data_email| try allocator.dupe(u8, data_email) else null);
        },
    }

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

pub fn fetchUpdate(self: *User) !void {
    _ = try self.context.users.fetch(self.id);
}

pub fn fetchUpdateIfIncomplete(self: *User) !void {
    if (self.meta.complete()) return;
    try self.fetchUpdate();
}

pub fn mention(self: *User) Mention {
    return .{ .user = self.id };
}

pub fn createDM(self: *User) !*Channel {
    return try self.context.createDM(self.id);
}
