const std = @import("std");

const Snowflake = @import("../models/snowflake.zig").Snowflake;

pub const Client = struct {
    gpa: std.mem.Allocator,
    guild_voice_servers: std.AutoHashMapUnmanaged(Snowflake, ManagedServerToken) = .empty,

    pub fn updateVoiceServer(
        client: *Client,
        guild_id: Snowflake,
        token: []const u8,
        endpoint: []const u8,
    ) !void {
        if (client.takeVoiceServer(guild_id)) |existing| {
            existing.deinit();
        }
        
        try client.putNoClobber(guild_id, try .init(client.gpa, token, endpoint));
        @memset(token, 0);
        @memset(endpoint, 0);
    }
    
    // Owner is responsible for de-initialising the managed server token
    pub fn takeVoiceServer(client: *Client, guild_id: Snowflake) ?ManagedServerToken {
        const removed_entry = client.guild_voice_servers.fetchRemove(guild_id) orelse return null;
        return removed_entry.value;
    }

    const ManagedServerToken = struct {
        gpa: std.mem.Allocator,
    
        token: []const u8,
        endpoint: []const u8,
        
        pub fn init(gpa: std.mem.Allocator, token: []const u8, endpoint: []const u8) !ManagedServerToken {
            const token_duped = try gpa.dupe(u8, token);
            errdefer gpa.free(token_duped);
            errdefer @memset(token_duped, 0);
            
            const endpoint_duped = try gpa.dupe(u8, endpoint);
            errdefer gpa.free(endpoint_duped);
            errdefer @memset(endpoint_duped, 0);
            
            return .{
                .token = token_duped,
                .endpoint = endpoint_duped,
            };
        }
        
        pub fn deinit(auth_server: ManagedServerToken) void {
            @memset(auth_server.token, 0);
            auth_server.gpa.free(auth_server.token);
            @memset(auth_server.endpoint, 0);
            auth_server.gpa.free(auth_server.endpoint);
        }
    };
};