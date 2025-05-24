const std = @import("std");

const Snowflake = @import("snowflake.zig").Snowflake;

pub fn Pool(comptime Structure: type) type {
    return struct {
        const PoolT = @This();

        allocator: std.mem.Allocator,
        inner_map: std.AutoArrayHashMapUnmanaged(Snowflake, *Structure),

        pub fn init(allocator: std.mem.Allocator) PoolT {
            return .{
                .allocator = allocator,
                .inner_map = .empty,
            };
        }

        pub fn deinit(self: *PoolT) void {
            self.inner_map.deinit(self.allocator);
        }

        pub fn clear(self: *PoolT) void {
            self.inner_map.clearRetainingCapacity();
        }

        pub fn slice(self: *PoolT) []*Structure {
            return self.inner_map.values();
        }

        pub fn add(self: *PoolT, structure: *Structure) !void {
            try self.inner_map.put(self.allocator, structure.id, structure);
        }

        pub fn remove(self: *PoolT, id: Snowflake) void {
            _ = self.inner_map.orderedRemove(id);
        }

        pub fn get(self: *PoolT, id: Snowflake) ?*Structure {
            return self.inner_map.get(id);
        }

        pub fn resolve(self: *PoolT, ref: anytype) !?*Structure {
            if (@TypeOf(ref) == *Structure or @TypeOf(ref) == *const Structure) return try self.resolve(ref.id);
            return self.get(try Snowflake.resolve(ref));
        }
    };
}

pub fn Cache(comptime Structure: type) type {
    const Context = @FieldType(Structure, "context");

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

        pub fn resolve(self: *CacheT, ref: anytype) !?*Structure {
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
                if (@hasDecl(Structure, "init")) {
                    get_result.value_ptr.*.init();
                }
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
