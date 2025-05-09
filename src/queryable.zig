pub fn Queryable(comptime Inner: type) type {
    return union(enum) {
        unknown: void,
        known: Inner,

        pub fn patch(self: *Queryable(Inner), val: ?Inner) void {
            if (val) |inner| self.* = .{ .known = inner };
        }
    };
}
