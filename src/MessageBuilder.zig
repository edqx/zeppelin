const std = @import("std");
const Snowflake = @import("snowflake.zig").Snowflake;

const MessageBuilder = @This();

pub const Mention = union(enum) {
    pub const Named = struct {
        name: []const u8,
        id: Snowflake,

        pub fn format(self: Named, comptime _: []const u8, _: std.fmt.FormatOptions, writer2: anytype) !void {
            try writer2.print("{s}:{}", .{ self.name, self.id });
        }
    };

    pub const Timestamp = struct {
        pub const Style = enum {
            short_time,
            long_time,
            short_date,
            long_date,
            short_date_time,
            long_date_time,
            relative,

            pub fn char(self: Style) u8 {
                return switch (self) {
                    .short_time => 't',
                    .long_time => 'T',
                    .short_date => 'd',
                    .long_date => 'D',
                    .short_date_time => 'f',
                    .long_date_time => 'F',
                    .relative => 'R',
                };
            }
        };

        timestamp: i64,
        style: ?Style,

        pub fn format(self: Timestamp, comptime _: []const u8, _: std.fmt.FormatOptions, writer2: anytype) !void {
            if (self.style) |style| {
                try writer2.print("{}:{c}", .{ self.timestamp, style.char() });
            } else {
                try writer2.print("{}", .{self.timestamp});
            }
        }
    };

    user: Snowflake,
    channel: Snowflake,
    role: Snowflake,
    slash_command: Named,
    emoji: Named,
    animated_emoji: Named,
    timestamp: Timestamp,
    // todo: guild navigation

    pub fn format(self: Mention, comptime _: []const u8, _: std.fmt.FormatOptions, writer2: anytype) !void {
        try writer2.print("<", .{});
        try writer2.print("{s}", .{switch (self) {
            .user => "@",
            .channel => "#",
            .role => "@&",
            .slash_command => "/",
            .emoji => ":",
            .animated_emoji => "a:",
            .timestamp => "t:",
        }});
        switch (self) {
            inline else => |e| try writer2.print("{}", .{e}),
        }
        try writer2.print(">", .{});
    }
};

allocator: std.mem.Allocator,

contents: std.ArrayListUnmanaged(u8) = .empty,

pub fn deinit(self: *MessageBuilder) void {
    self.contents.deinit(self.allocator);
}

pub fn writer(self: *MessageBuilder) std.ArrayListUnmanaged(u8).Writer {
    return self.contents.writer(self.allocator);
}
