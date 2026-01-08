const std = @import("std");

const Channel = @import("../models/Channel.zig");

const ApplicationCommandBuilder = @This();

pub fn anyFieldsSet(s: anytype) bool {
    return inline for (@typeInfo(@TypeOf(s)).@"struct".fields) |field| {
        if (@field(s, field.name)) break true;
    } else false;
}

pub fn EnumBitfield(E: type) type {
    var packed_struct_info: std.builtin.Type.Struct = .{
        .decls = &.{},
        .fields = &.{},
        .is_tuple = false,
        .layout = .@"packed",
    };
    for (@typeInfo(E).@"enum".fields) |field| {
        packed_struct_info.fields = packed_struct_info.fields ++ .{std.builtin.Type.StructField{
            .name = field.name,
            .type = bool,
            .alignment = 0,
            .is_comptime = false,
            .default_value_ptr = &false,
        }};
    }
    return @Type(.{ .@"struct" = packed_struct_info });
}

pub const Type = enum(i32) {
    chat_input = 1,
    user,
    message,
    primary_entry_point,
};

pub const ContextType = enum {
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
        description: std.Io.Writer.Allocating,
        sub_commands: std.ArrayList(SubCommand),

        pub fn deinit(self: Group) void {
            for (self.sub_commands.items) |sub_command| {
                sub_command.deinit();
            }
            self.sub_commands.deinit();
            self.description.deinit();
        }

        pub fn addSubCommand(
            self: *Group,
            sub_command: SubCommand,
        ) !*Option {
            const ptr = try self.sub_commands.addOne();
            ptr.* = sub_command;
            return &ptr;
        }

        pub fn jsonStringify(self: Group, jw: anytype) !void {
            try jw.objectField("name");
            try jw.write(self.name);

            try jw.objectField("description");
            try jw.write(self.description.written());

            try jw.objectField("options");
            try jw.beginArray();
            for (self.sub_commands.items) |sub_command| {
                try jw.write(@as(Option, .{ .sub_command = sub_command }));
            }
            try jw.endArray();
        }
    };

    name: []const u8,
    description: std.Io.Writer.Allocating,
    options: std.ArrayList(Option),

    pub fn deinit(self: SubCommand) void {
        for (self.options.items) |option| {
            option.deinit();
        }
        self.options.deinit();
        self.description.deinit();
    }

    pub fn addOption(
        self: *SubCommand,
        comptime option_type: std.meta.Tag(Option),
        option: @FieldType(Option, @tagName(option_type)),
    ) !*@TypeOf(option) {
        const ptr = try self.options.addOne();
        ptr.* = @unionInit(Option, @tagName(option_type), option);
        return &@field(ptr, @tagName(option_type));
    }

    pub fn jsonStringify(self: SubCommand, jw: anytype) !void {
        try jw.objectField("name");
        try jw.write(self.name);

        try jw.objectField("description");
        try jw.write(self.description.written());

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
    description: std.Io.Writer.Allocating,
    required: bool,

    pub fn jsonStringify(self: InputOption, jw: anytype) !void {
        try jw.objectField("name");
        try jw.write(self.name);

        try jw.objectField("description");
        try jw.write(self.description.written());

        try jw.objectField("required");
        try jw.write(self.required);
    }
};

fn jsonStringifyChoices(choices: anytype, jw: anytype) !void {
    if (choices.len > 0) {
        try jw.objectField("choices");
        try jw.beginArray();
        for (choices) |choice| {
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
    choices: std.ArrayList(Choice),
    min_length: ?usize = null,
    max_length: ?usize = null,
    autocomplete: ?bool = null,

    pub fn jsonStringify(self: StringInput, jw: anytype) !void {
        try jw.write(self.option);
        try jsonStringifyChoices(self.choices.items, jw);

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
    choices: std.ArrayList(Choice),
    min: ?i64 = null,
    max: ?i64 = null,
    autocomplete: ?bool = null,

    pub fn jsonStringify(self: IntegerInput, jw: anytype) !void {
        try jw.write(self.option);
        try jsonStringifyChoices(self.choices.items, jw);

        if (self.min) |min| {
            try jw.objectField("min_value");
            try jw.write(min);
        }

        if (self.max) |max| {
            try jw.objectField("max_value");
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
    choices: std.ArrayList(Choice),
    min: ?f64 = null,
    max: ?f64 = null,
    autocomplete: ?bool = null,

    pub fn jsonStringify(self: NumberInput, jw: anytype) !void {
        try jw.write(self.option);
        try jsonStringifyChoices(self.choices.items, jw);

        if (self.min) |min| {
            try jw.objectField("min_value");
            try jw.write(min);
        }

        if (self.max) |max| {
            try jw.objectField("max_value");
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
    channel_types: ?EnumBitfield(Channel.Type),

    pub fn jsonStringify(self: ChannelInput, jw: anytype) !void {
        try jw.write(self.option);

        if (self.channel_types) |channel_types| {
            try jw.objectField("channel_types");
            try jw.beginArray();
            for (@typeInfo(Channel.Type).@"struct".fields) |field| {
                if (@field(channel_types, field.name)) {
                    try jw.write(@field(Channel.Type, field.name));
                }
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

    pub fn deinit(self: Option) void {
        switch (self) {
            inline else => |option| if (@hasDecl(@TypeOf(option), "deinit"))
                option.deinit(),
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

description: std.Io.Writer.Allocating,

contexts: ?EnumBitfield(ContextType) = null,
integrations: ?EnumBitfield(IntegrationType) = null,

options: std.ArrayList(Option),
nsfw: bool = false,

pub fn init(allocator: std.mem.Allocator, @"type": Type, name: []const u8) !ApplicationCommandBuilder {
    return .{
        .name = name,
        .type = @"type",
        .description = try .initCapacity(allocator, 100),
        .options = .empty,
    };
}

pub fn deinit(self: ApplicationCommandBuilder) void {
    for (self.options.items) |option| {
        option.deinit();
    }
    self.options.deinit();
    self.description.deinit();
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
    try jw.write(self.description.written());
    {
        try jw.objectField("type");
        try jw.write(@intFromEnum(self.type));
    }
    if (self.contexts) |contexts| {
        try jw.objectField("contexts");
        try jw.beginArray();
        for (@typeInfo(ContextType).@"struct".fields) |field| {
            if (@field(contexts, field.name)) {
                try jw.write(@field(ContextType, field.name));
            }
        }
        try jw.endArray();
    } else {
        try jw.objectField("contexts");
        try jw.write(null);
    }

    if (self.integrations) |integrations| {
        if (integrations) {
            try jw.objectField("integration_types");
            try jw.beginArray();
            for (@typeInfo(IntegrationType).@"struct".fields) |field| {
                if (@field(integrations, field.name)) {
                    try jw.write(@field(IntegrationType, field.name));
                }
            }
            try jw.endArray();
        }
    } else {
        try jw.objectField("integration_types");
        try jw.write(null);
    }

    if (self.options.items.len > 0) {
        try jw.objectField("options");
        try jw.beginArray();
        for (self.options.items) |option| {
            try jw.write(option);
        }
        try jw.endArray();
    }

    try jw.objectField("nsfw");
    try jw.write(self.nsfw);

    try jw.endObject();
}
