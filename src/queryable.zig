const std = @import("std");

const Elective = @import("gateway_message.zig").Elective;

pub fn QueriedFields(comptime Structure: type, comptime fields: []const [:0]const u8) type {
    var queried_fields: []const std.builtin.Type.StructField = &.{};

    for (fields) |field_name| {
        if (std.mem.eql(u8, field_name, "context")) continue;
        if (std.mem.eql(u8, field_name, "id")) continue;

        queried_fields = queried_fields ++ .{@as(std.builtin.Type.StructField, .{
            .alignment = @alignOf(bool),
            .default_value_ptr = &false,
            .is_comptime = false,
            .name = field_name,
            .type = bool,
        })};
    }

    const queried_fields_const = queried_fields;

    const QueryMap = @Type(.{ .@"struct" = .{
        .layout = .auto,
        .backing_integer = null,
        .fields = queried_fields_const,
        .decls = &.{},
        .is_tuple = false,
    } });

    return struct {
        const QueriedFieldsT = @This();

        pub const none: QueriedFieldsT = .{};

        fields: QueryMap = .{},

        pub fn complete(self: *QueriedFieldsT) bool {
            inline for (queried_fields_const) |field| {
                @setEvalBranchQuota(10000);
                const field_tag = comptime std.meta.stringToEnum(
                    std.meta.FieldEnum(QueryMap),
                    field.name,
                ) orelse unreachable;
                if (!self.queried(field_tag)) return false;
            }
            return true;
        }

        pub inline fn queried(self: *QueriedFieldsT, field: std.meta.FieldEnum(QueryMap)) bool {
            return @field(self.fields, @tagName(field));
        }

        pub fn patch(
            self: *QueriedFieldsT,
            comptime field: std.meta.FieldEnum(QueryMap),
            val: @FieldType(Structure, @tagName(field)),
        ) void {
            const struct_ptr: *Structure = @alignCast(@fieldParentPtr("meta", self));
            @field(self.fields, @tagName(field)) = true;
            @field(struct_ptr, @tagName(field)) = val;
        }

        pub fn patchElective(
            self: *QueriedFieldsT,
            comptime field: std.meta.FieldEnum(QueryMap),
            val: Elective(@FieldType(Structure, @tagName(field))),
        ) void {
            switch (val) {
                .not_given => {},
                .val => |inner| self.patch(field, inner),
            }
        }
    };
}
