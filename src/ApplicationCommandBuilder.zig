const std = @import("std");

const Channel = @import("structures/Channel.zig");

const ApplicationCommandBuilder = @This();

pub fn anyFieldsSet(s: anytype) bool {
    return inline for (@typeInfo(@TypeOf(s)).@"struct".fields) |field| {
        if (@field(s, field.name)) break true;
    } else false;
}

pub const Type = enum(i32) {
    chat_input = 1,
    user,
    message,
    primary_entry_point,
};

pub const Context = enum {
    guild,
    bot_dm,
    private_channel,
};

pub const IntegrationType = enum {
    guild_install,
    user_install,
};

pub const SubCommand = struct {
    pub const Group = struct {
        name: []const u8,
        description: std.BoundedArray(u8, 100) = .{},
        sub_commands: std.ArrayListUnmanaged(SubCommand) = .empty,

        pub fn deinit(self: Group, allocator: std.mem.Allocator) void {
            for (self.sub_commands.items) |sub_command| {
                sub_command.deinit(allocator);
            }
            var sub_commands_var = self.sub_commands;
            sub_commands_var.deinit(allocator);
        }

        pub fn addSubCommand(
            self: *Group,
            allocator: std.mem.Allocator,
            sub_command: SubCommand,
        ) !*Option {
            const ptr = try self.sub_commands.addOne(allocator);
            ptr.* = sub_command;
            return &ptr;
        }

        pub fn jsonStringify(self: Group, jw: anytype) !void {
            try jw.objectField("name");
            try jw.write(self.name);

            try jw.objectField("description");
            try jw.write(self.description.slice());

            try jw.objectField("options");
            try jw.beginArray();
            for (self.sub_commands.items) |sub_command| {
                try jw.write(@as(Option, .{ .sub_command = sub_command }));
            }
            try jw.endArray();
        }
    };

    name: []const u8,
    description: std.BoundedArray(u8, 100) = .{},
    options: std.ArrayListUnmanaged(Option) = .{},

    pub fn deinit(self: SubCommand, allocator: std.mem.Allocator) void {
        for (self.options.items) |option| {
            option.deinit(allocator);
        }
        var options_var = self.options;
        options_var.deinit(allocator);
    }

    pub fn addOption(
        self: *SubCommand,
        allocator: std.mem.Allocator,
        comptime option_type: std.meta.Tag(Option),
        option: @FieldType(Option, @tagName(option_type)),
    ) !*@TypeOf(option) {
        const ptr = try self.options.addOne(allocator);
        ptr.* = @unionInit(Option, @tagName(option_type), option);
        return &@field(ptr, @tagName(option_type));
    }

    pub fn jsonStringify(self: SubCommand, jw: anytype) !void {
        try jw.objectField("name");
        try jw.write(self.name);

        try jw.objectField("description");
        try jw.write(self.description.slice());

        try jw.objectField("options");
        try jw.beginArray();
        for (self.options.items) |option| {
            try jw.write(option);
        }
        try jw.endArray();
    }
};

pub const InputOption = struct {
    name: []const u8,
    description: std.BoundedArray(u8, 100) = .{},
    required: bool,

    pub fn jsonStringify(self: InputOption, jw: anytype) !void {
        try jw.objectField("name");
        try jw.write(self.name);

        try jw.objectField("description");
        try jw.write(self.description.slice());

        try jw.objectField("required");
        try jw.write(self.required);
    }
};

fn jsonStringifyChoices(choices: anytype, jw: anytype) !void {
    if (choices.len > 0) {
        try jw.objectField("choices");
        try jw.beginArray();
        for (choices.slice()) |choice| {
            try jw.write(choice);
        }
        try jw.endArray();
    }
}

pub const StringInput = struct {
    pub const Choice = struct {
        name: []const u8,
        value: []const u8,
    };

    option: InputOption,
    choices: std.BoundedArray(Choice, 25) = .{},
    min_length: ?usize = null,
    max_length: ?usize = null,
    autocomplete: ?bool = null,

    pub fn jsonStringify(self: StringInput, jw: anytype) !void {
        try jw.write(self.option);
        try jsonStringifyChoices(self.choices, jw);

        if (self.min_length) |min_length| {
            try jw.objectField("min_length");
            try jw.write(min_length);
        }

        if (self.max_length) |max_length| {
            try jw.objectField("max_length");
            try jw.write(max_length);
        }

        if (self.autocomplete) |autocomplete| {
            try jw.objectField("autocomplete");
            try jw.write(autocomplete);
        }
    }
};

pub const IntegerInput = struct {
    pub const Choice = struct {
        name: []const u8,
        value: i64,
    };

    option: InputOption,
    choices: std.BoundedArray(Choice, 25) = .{},
    min: ?i64 = null,
    max: ?i64 = null,
    autocomplete: ?bool = null,

    pub fn jsonStringify(self: IntegerInput, jw: anytype) !void {
        try jw.write(self.option);
        try jsonStringifyChoices(self.choices, jw);

        if (self.min) |min| {
            try jw.objectField("min");
            try jw.write(min);
        }

        if (self.max) |max| {
            try jw.objectField("max");
            try jw.write(max);
        }

        if (self.autocomplete) |autocomplete| {
            try jw.objectField("autocomplete");
            try jw.write(autocomplete);
        }
    }
};

pub const NumberInput = struct {
    pub const Choice = struct {
        name: []const u8,
        value: f64,
    };

    option: InputOption,
    choices: std.BoundedArray(Choice, 25) = .{},
    min: ?i64 = null,
    max: ?i64 = null,
    autocomplete: ?bool = null,

    pub fn jsonStringify(self: NumberInput, jw: anytype) !void {
        try jw.write(self.option);
        try jsonStringifyChoices(self.choices, jw);

        if (self.min) |min| {
            try jw.objectField("min");
            try jw.write(min);
        }

        if (self.max) |max| {
            try jw.objectField("max");
            try jw.write(max);
        }

        if (self.autocomplete) |autocomplete| {
            try jw.objectField("autocomplete");
            try jw.write(autocomplete);
        }
    }
};

pub const ChannelInput = struct {
    option: InputOption,
    channel_types: std.EnumArray(Channel.Type, bool),

    pub fn jsonStringify(self: ChannelInput, jw: anytype) !void {
        try jw.write(self.option);

        const any_channel_types_set = for (self.channel_types.values) |channel_type| {
            if (channel_type) break true;
        } else false;

        if (any_channel_types_set) {
            try jw.objectField("channel_types");
            try jw.beginArray();
            var channel_types_var = self.channel_types;
            var channel_types_iter = channel_types_var.iterator();
            while (channel_types_iter.next()) |entry| {
                if (entry.value.*) try jw.write(entry.key);
            }
            try jw.endArray();
        }
    }
};

pub const Option = union(enum(i32)) {
    sub_command_group: SubCommand.Group,
    sub_command: SubCommand,
    string: StringInput,
    integer: IntegerInput,
    boolean: InputOption,
    user: InputOption,
    channel: ChannelInput,
    role: InputOption,
    mentionable: InputOption,
    number: NumberInput,
    attachment: InputOption,

    pub fn deinit(self: Option, allocator: std.mem.Allocator) void {
        switch (self) {
            inline else => |option| if (@hasDecl(@TypeOf(option), "deinit"))
                option.deinit(allocator),
        }
    }

    pub fn jsonStringify(self: Option, jw: anytype) !void {
        try jw.beginObject();
        {
            try jw.objectField("type");
            try jw.write(@intFromEnum(self));

            switch (self) {
                inline else => |option| try jw.write(option),
            }
        }
        try jw.endObject();
    }
};

name: []const u8, // TODO: localisations
type: Type,

description: std.BoundedArray(u8, 100) = .{}, // TODO: localisations

contexts: ?std.enums.EnumArray(Context, bool) = .initFill(false),
integration_types: std.enums.EnumArray(IntegrationType, bool) = .initFill(false),

options: std.ArrayListUnmanaged(Option) = .empty,

pub fn deinit(self: ApplicationCommandBuilder, allocator: std.mem.Allocator) void {
    for (self.options.items) |option| {
        option.deinit(allocator);
    }
    var options_var = self.options;
    options_var.deinit(allocator);
}

pub fn descriptionWriter(self: *ApplicationCommandBuilder) std.BoundedArray(u8, 100).Writer {
    return self.description.writer();
}

pub fn descriptionFmt(self: *ApplicationCommandBuilder, comptime fmt: []const u8, args: anytype) !void {
    try self.descriptionWriter().print(fmt, args);
}

pub fn addOption(
    self: *ApplicationCommandBuilder,
    allocator: std.mem.Allocator,
    comptime option_type: std.meta.Tag(Option),
    option: @FieldType(Option, @tagName(option_type)),
) !*@TypeOf(option) {
    const ptr = try self.options.addOne(allocator);
    ptr.* = @unionInit(Option, @tagName(option_type), option);
    return &@field(ptr, @tagName(option_type));
}

pub fn jsonStringify(self: ApplicationCommandBuilder, jw: anytype) !void {
    try jw.beginObject();
    {
        try jw.objectField("name");
        try jw.write(self.name);
    }
    try jw.objectField("description");
    try jw.write(self.description.slice());
    {
        try jw.objectField("type");
        try jw.write(@intFromEnum(self.type));
    }
    if (self.contexts) |contexts| {
        // std.EnumArray.iterator expects a pointer to mutable data,
        // we don't have that.
        var contexts_var = contexts;
        const any_contexts_set = for (contexts.values) |context| {
            if (context) break true;
        } else false;

        if (any_contexts_set) {
            try jw.objectField("contexts");
            try jw.beginArray();
            var contexts_iter = contexts_var.iterator();
            while (contexts_iter.next()) |entry| {
                if (entry.value.*) try jw.write(entry.key);
            }
            try jw.endArray();
        }
    } else {
        try jw.objectField("contexts");
        try jw.write(null);
    }

    const any_integration_types_set = for (self.integration_types.values) |integration_type| {
        if (integration_type) break true;
    } else false;

    if (any_integration_types_set) {
        try jw.objectField("integration_types");
        try jw.beginArray();
        // std.EnumArray.iterator expects a pointer to mutable data,
        // we don't have that.
        var integration_types_var = self.integration_types;
        var integration_types = integration_types_var.iterator();
        while (integration_types.next()) |entry| {
            if (entry.value.*) try jw.write(entry.key);
        }
        try jw.endArray();
    }

    if (self.options.items.len > 0) {
        try jw.objectField("options");
        try jw.beginArray();
        for (self.options.items) |option| {
            try jw.write(option);
        }
        try jw.endArray();
    }

    try jw.endObject();
}
