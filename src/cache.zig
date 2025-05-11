const std = @import("std");

const Snowflake = @import("snowflake.zig").Snowflake;

pub fn Cache(comptime Structure: type, comptime Context: type) type {
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

        pub fn deinit(self: *CacheT) void {
            var values = self.inner_map.valueIterator();
            while (values.next()) |val_ptr| {
                val_ptr.*.deinit();
            }
            self.inner_map.deinit(self.allocator);
            self.pool.deinit();
        }

        pub fn get(self: *CacheT, id: Snowflake) ?*Structure {
            return self.inner_map.get(id);
        }

        pub fn resolve(self: *CacheT, ref: anytype) ?*Structure {
            if (@TypeOf(ref) == *Structure or @TypeOf(ref) == *const Structure) return ref;
            return self.get(try Snowflake.resolve(ref));
        }

        pub fn touch(self: *CacheT, context: Context, id: Snowflake) !*Structure {
            const get_result = try self.inner_map.getOrPut(self.allocator, id);
            if (!get_result.found_existing) {
                get_result.value_ptr.* = try self.pool.create();
                get_result.value_ptr.*.* = .{
                    .context = context,
                    .id = id,
                };
            }
            return get_result.value_ptr.*;
        }

        pub fn patch(self: *CacheT, context: Context, id: Snowflake, data: Structure.Data) !*Structure {
            const structure = try self.touch(context, id);
            try structure.patch(data);
            return structure;
        }
    };
}
