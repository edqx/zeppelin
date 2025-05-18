const std = @import("std");

pub fn Base64Writer(UnderlyingWriter: anytype) !void {
    return struct {
        pub const Writer = std.io.Writer(@This(), UnderlyingWriter.Error, encodeWrite);

        underlying_writer: UnderlyingWriter,

        pub fn encodeWrite(self: @This(), bytes: []const u8) !usize {
            try std.base64.standard.Encoder.encodeWriter(self.underlying_writer, bytes);
            return bytes.len;
        }
    };
}

pub fn base64Writer(underlying_writer: anytype) Base64Writer(@TypeOf(underlying_writer)) {
    return .{ .underlying_writer = underlying_writer };
}
