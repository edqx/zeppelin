const std = @import("std");

const Snowflake = @import("snowflake.zig").Snowflake;

const gateway_message = @import("../gateway/gateway_message.zig");

pub const Permissions = packed struct(Permissions.Int) {
    pub const Int = i64;

    pub const Overwrite = struct {
        pub const Type = enum {
            role,
            member,
        };

        id: Snowflake,
        type: Type,
        allow: Permissions,
        deny: Permissions,

        pub fn parseFromGatewayData(data: gateway_message.PermissionsOverwrite) !Overwrite {
            return .{
                .id = try .resolve(data.id),
                .type = @enumFromInt(data.type),
                .allow = try .parseFromGatewayData(data.allow),
                .deny = try .parseFromGatewayData(data.deny),
            };
        }

        pub fn apply(self: Overwrite, permissions: Permissions) Permissions {
            return permissions.withDenied(self.deny).withAllowed(self.allow);
        }
    };

    create_instant_invite: bool = false,
    kick_members: bool = false,
    ban_members: bool = false,
    administrator: bool = false,
    manage_channels: bool = false,
    manage_guild: bool = false,
    add_reactions: bool = false,
    view_audit_log: bool = false,
    priority_speaker: bool = false,
    stream: bool = false,
    view_channel: bool = false,
    send_messages: bool = false,
    send_tts_messages: bool = false,
    manage_messages: bool = false,
    embed_links: bool = false,
    attach_files: bool = false,
    read_message_history: bool = false,
    mention_everyone: bool = false,
    use_external_emojis: bool = false,
    view_guild_insights: bool = false,
    connect: bool = false,
    speak: bool = false,
    mute_members: bool = false,
    deafen_members: bool = false,
    move_members: bool = false,
    use_vad: bool = false,
    change_nickname: bool = false,
    manage_nicknames: bool = false,
    manage_roles: bool = false,
    manage_webhooks: bool = false,
    manage_guild_expressions: bool = false,
    use_application_commands: bool = false,
    request_to_speak: bool = false,
    manage_events: bool = false,
    manage_threads: bool = false,
    create_public_threads: bool = false,
    create_private_threads: bool = false,
    use_external_stickers: bool = false,
    send_messages_in_threads: bool = false,
    use_embedded_activities: bool = false,
    moderate_members: bool = false,
    view_creator_monetization_analytics: bool = false,
    use_soundboard: bool = false,
    create_guild_expressions: bool = false,
    create_events: bool = false,
    use_external_sounds: bool = false,
    send_voice_messages: bool = false,
    _packed1: enum(u2) { unset, _ } = .unset,
    send_polls: bool = false,
    use_external_apps: bool = false,
    _packed2: enum(u13) { unset, _ } = .unset,

    pub const all: Permissions = blk: {
        var res: Permissions = .{};
        for (@typeInfo(Permissions).@"struct".fields) |field| {
            if (field.type == bool) {
                @field(res, field.name) = true;
            }
        }
        break :blk res;
    };

    pub fn parseFromGatewayData(data: gateway_message.Permissions) !Permissions {
        const permission_integer = try std.fmt.parseInt(Permissions.Int, data, 10);
        return @bitCast(permission_integer);
    }

    pub fn withAllowed(self: Permissions, other: Permissions) Permissions {
        return @bitCast(@as(Permissions.Int, @bitCast(self)) | @as(Permissions.Int, @bitCast(other)));
    }

    pub fn withDenied(self: Permissions, other: Permissions) Permissions {
        return @bitCast(@as(Permissions.Int, @bitCast(self)) & ~@as(Permissions.Int, @bitCast(other)));
    }
};
