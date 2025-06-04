const std = @import("std");

const ApplicationCommandBuilder = @This();

pub const Type = enum(i32) {
    chat_input = 1,
    user,
    message,
    primary_entry_point,
};

pub const Context = enum(i32) {
    guild,
    bot_dm,
    private_channel,
};

pub const IntegrationType = enum(i32) {
    guild_install,
    user_install,
};

allocator: std.mem.Allocator,

_name: []const u8 = "", // TODO: localisations
_description: std.BoundedArray(u8, 100) = .{}, // TODO: localisations

type: Type,
_contexts: std.ArrayListUnmanaged(Context) = .empty,
_integration_types: std.ArrayListUnmanaged(IntegrationType) = .empty,

pub fn init(allocator: std.mem.Allocator, @"type": Type) ApplicationCommandBuilder {
    return .{ .allocator = allocator, .type = @"type" };
}

pub fn deinit(self: *ApplicationCommandBuilder) void {
    self._contexts.deinit(self.allocator);
    self._contexts = .empty;
    self._integration_types.deinit(self.allocator);
    self._integration_types = .empty;
    self._description = .{};
    self.allocator.free(self._name);
    self._name = "";
}

pub fn name(self: *ApplicationCommandBuilder, _name: []const u8) !void {
    self.allocator.free(self._name);
    self._name = try self.allocator.dupe(u8, _name);
}

pub fn descriptionWriter(self: *ApplicationCommandBuilder) std.BoundedArray(u8, 100).Writer {
    return self._description.writer();
}

pub fn description(self: *ApplicationCommandBuilder, comptime fmt: []const u8, args: anytype) !void {
    try self.descriptionWriter().print(fmt, args);
}

pub fn context(self: *ApplicationCommandBuilder, ctx: Context) !void {
    try self._contexts.append(ctx);
}

pub fn integrationType(self: *ApplicationCommandBuilder, integration_type: IntegrationType) !void {
    try self._integration_types.append(integration_type);
}

pub fn jsonStringify(self: ApplicationCommandBuilder, jw: anytype) !void {
    try jw.beginObject();
    {
        try jw.objectField("name");
        try jw.write(self._name);
    }
    if (self._description.len > 0) {
        try jw.objectField("description");
        try jw.write(self._description.slice());
    }
    {
        try jw.objectField("type");
        try jw.write(@intFromEnum(self.type));
    }
    if (self._contexts.items.len > 0) {
        try jw.objectField("contexts");
        try jw.beginArray();
        for (self._contexts.items) |_context| {
            try jw.write(@intFromEnum(_context));
        }
        try jw.endArray();
    }
    if (self._integration_types.items.len > 0) {
        try jw.objectField("integration_types");
        try jw.beginArray();
        for (self._integration_types.items) |integration_type| {
            try jw.write(@intFromEnum(integration_type));
        }
        try jw.endArray();
    }

    try jw.endObject();
}
