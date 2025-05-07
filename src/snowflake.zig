const std = @import("std");

pub const Snowflake = packed struct(u64) {
    pub const Int = u64;

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
};
