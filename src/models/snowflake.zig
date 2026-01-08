const std = @import("std");

pub const Snowflake = packed struct(u64) {
    pub const max_size = 20;
    pub const nil: Snowflake = @bitCast(@as(u64, 0));

    pub fn resolve(ref: anytype) !Snowflake {
        const RefT = @TypeOf(ref);
        if (RefT == Snowflake) return ref;
        if (RefT == u64) return @bitCast(ref);
        if (RefT == comptime_int) return try .resolve(@as(u64, ref));
        // if (@TypeOf(ref, @as([]const u8, undefined)) == []const u8) {
        //     const snowflake_int = try std.fmt.parseInt(Int, ref, 10);
        //     return resolve(snowflake_int);
        // }
        // @compileError("Unknown reference type to resolve: " ++ @typeName(RefT));
        const snowflake_int = try std.fmt.parseInt(u64, ref, 10);
        return resolve(snowflake_int);
    }

    pub inline fn from(comptime ref: anytype) Snowflake {
        @setEvalBranchQuota(2000);
        comptime return resolve(ref) catch unreachable;
    }

    increment: u12,
    internal_process_id: u5,
    internal_worker_id: u5,
    timestamp: u42,

    pub fn format(self: Snowflake, writer: *std.Io.Writer) !void {
        try writer.print("{}", .{@as(u64, @bitCast(self))});
    }

    pub fn jsonStringify(self: Snowflake, jw: anytype) !void {
        try jw.beginWriteRaw();
        try jw.writer.print("\"{f}\"", .{self});
        jw.endWriteRaw();
    }
    
    pub fn formatBuffer(self: Snowflake, buffer: *[max_size]u8) []u8 {
        return std.fmt.bufPrint(buffer, "{f}", .{self}) catch unreachable;
    }
};
