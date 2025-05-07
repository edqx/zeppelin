pub fn Queryable(comptime Inner: type) type {
    return union(enum) {
        unknown: void,
        known: Inner,
    };
}
