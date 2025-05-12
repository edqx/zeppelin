pub const Authentication = union(enum) {
    token: []const u8,

    pub fn resolve(self: Authentication) []const u8 {
        return switch (self) {
            .token => |token| token,
        };
    }
};
