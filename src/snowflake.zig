const std = @import("std");

pub const Snowflake = packed struct(u64) {
    pub const Int = u64;

    pub const nil: Snowflake = @bitCast(@as(u64, 0));

    pub fn resolve(ref: anytype) !Snowflake {
        const RefT = @TypeOf(ref);
        if (RefT == Snowflake) return ref;
        if (RefT == Int) return @bitCast(ref);
        // if (@TypeOf(ref, @as([]const u8, undefined)) == []const u8) {
        //     const snowflake_int = try std.fmt.parseInt(Int, ref, 10);
        //     return resolve(snowflake_int);
        // }
        // @compileError("Unknown reference type to resolve: " ++ @typeName(RefT));
        const snowflake_int = try std.fmt.parseInt(Int, ref, 10);
        return resolve(snowflake_int);
    }

    increment: u12,
    internal_process_id: u5,
    internal_worker_id: u5,
    timestamp: u42,

    pub fn format(self: Snowflake, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{}", .{@as(Int, @bitCast(self))});
    }

    pub fn jsonStringify(self: Snowflake, jw: anytype) !void {
        try jw.beginWriteRaw();
        try jw.stream.print("\"{}\"", .{self});
        jw.endWriteRaw();
    }
};
