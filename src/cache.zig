const std = @import("std");

const Snowflake = @import("snowflake.zig").Snowflake;

pub fn Cache(comptime Structure: type) type {
    return struct {
        const CacheT = @This();

        allocator: std.mem.Allocator,

        pool: std.heap.MemoryPool(Structure),
        inner_map: std.AutoHashMapUnmanaged(Snowflake, *Structure),

        pub fn init(allocator: std.mem.Allocator) CacheT {
            return .{
                .allocator = allocator,
                .pool = std.heap.MemoryPool(Structure).init(allocator),
                .inner_map = .empty,
            };
        }

        pub fn get(self: *CacheT, id: Snowflake) !?*Structure {
            return self.inner_map.get(self.allocator, id);
        }

        pub fn resolve(self: *CacheT, ref: anytype) !?*Structure {
            return self.get(try Snowflake.resolve(ref));
        }

        pub fn patch(self: *CacheT, data: Structure.Data) !*Structure {
            const get_result = try self.inner_map.getOrPut(self.allocator, try Snowflake.resolve(data.id));
            if (!get_result.found_existing) {
                get_result.value_ptr.* = try self.pool.create();
                try get_result.value_ptr.*.init(self.allocator, data);
            } else {
                try get_result.value_ptr.*.patch(self.allocator, data);
            }

            return get_result.value_ptr.*;
        }
    };
}
