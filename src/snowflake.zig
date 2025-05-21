const std = @import("std");

pub const Snowflake = packed struct(u64) {
    pub const Int = u64;

    pub const nil: Snowflake = @bitCast(@as(u64, 0));

    pub fn resolve(ref: anytype) !Snowflake {
        const ref_type = @TypeOf(ref);
        if (ref_type == Snowflake) return ref;
        if (ref_type == Int) return @bitCast(ref);
        if (ref_type == []u8 or ref_type == []const u8) {
            const snowflake_int = try std.fmt.parseInt(Int, ref, 10);
            return resolve(snowflake_int);
        }
        @compileError("Unknown reference type to resolve: " ++ @typeName(ref_type));
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
