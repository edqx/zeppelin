const std = @import("std");
const Snowflake = @import("../snowflake.zig").Snowflake;

pub const Data = @import("../gateway_message.zig").User;

const User = @This();

id: Snowflake,
username: []const u8,
discriminator: []const u8,

pub fn init(self: *User, gpa: std.mem.Allocator, data: Data) !void {
    self.id = try .resolve(data.id);
    self.username = try gpa.dupe(u8, data.username);
    self.discriminator = try gpa.dupe(u8, data.discriminator);
}

pub fn patch(self: *User, gpa: std.mem.Allocator, data: Data) !void {
    gpa.free(self.username);
    gpa.free(self.discriminator);
    self.username = try gpa.dupe(u8, data.username);
    self.discriminator = try gpa.dupe(u8, data.discriminator);
}
