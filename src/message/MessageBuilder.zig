const std = @import("std");
const datetime = @import("datetime").datetime;

const Snowflake = @import("../models/snowflake.zig").Snowflake;
const Message = @import("../models/Message.zig");
const Interaction = @import("../models/ephemeral/Interaction.zig");
const Color = Message.Color;

const MessageBuilder = @This();

pub const Mention = union(enum) {
    pub const Named = struct {
        name: []const u8,
        id: Snowflake,

        pub fn format(self: Named, writer2: *std.io.Writer) !void {
            try writer2.print("{s}:{f}", .{ self.name, self.id });
        }
    };

    pub const Timestamp = struct {
        pub const Style = enum {
            short_time,
            long_time,
            short_date,
            long_date,
            short_date_time,
            long_date_time,
            relative,

            pub fn char(self: Style) u8 {
                return switch (self) {
                    .short_time => 't',
                    .long_time => 'T',
                    .short_date => 'd',
                    .long_date => 'D',
                    .short_date_time => 'f',
                    .long_date_time => 'F',
                    .relative => 'R',
                };
            }
        };

        timestamp: i64,
        style: ?Style,

        pub fn format(self: Timestamp, writer2: *std.io.Writer) !void {
            if (self.style) |style| {
                try writer2.print("{}:{c}", .{ self.timestamp, style.char() });
            } else {
                try writer2.print("{}", .{self.timestamp});
            }
        }
    };

    user: Snowflake,
    channel: Snowflake,
    role: Snowflake,
    slash_command: Named,
    emoji: Named,
    animated_emoji: Named,
    timestamp: Timestamp,
    // todo: guild navigation

    pub fn format(self: Mention, writer2: *std.io.Writer) !void {
        try writer2.print("<", .{});
        try writer2.print("{s}", .{switch (self) {
            .user => "@",
            .channel => "#",
            .role => "@&",
            .slash_command => "/",
            .emoji => ":",
            .animated_emoji => "a:",
            .timestamp => "t:",
        }});
        switch (self) {
            inline else => |e| try writer2.print("{f}", .{e}),
        }
        try writer2.print(">", .{});
    }
};

pub const FieldWriter = struct {
    name: std.Io.Writer.Allocating,
    value: std.Io.Writer.Allocating,
    display_inline: bool = false,

    pub fn init(allocator: std.mem.Allocator) !FieldWriter {
        return .{
            .name = try .init(allocator),
            .value = try .init(allocator),
            .display_inline = false,
        };
    }

    pub fn deinit(self: FieldWriter) void {
        self.value.deinit();
        self.name.deinit();
    }

    pub fn jsonStringify(self: FieldWriter, jw: anytype) !void {
        try jw.beginObject();
        {
            try jw.objectField("name");
            try jw.write(self.name.writer.buffered());
        }
        {
            try jw.objectField("value");
            try jw.write(self.value.writer.buffered());
        }
        if (self.display_inline) {
            try jw.objectField("inline");
            try jw.write(self.display_inline);
        }
        try jw.endObject();
    }
};

pub const EmbedBuilder = struct {
    const ImageRef = union(enum) {
        url: []const u8,
        attachment: []const u8,

        pub fn dupe(self: ImageRef, allocator: std.mem.Allocator) !ImageRef {
            return switch (self) {
                inline .url, .attachment => |s, t| @unionInit(ImageRef, @tagName(t), try allocator.dupe(u8, s)),
            };
        }

        pub fn deinit(self: ImageRef, allocator: std.mem.Allocator) void {
            switch (self) {
                inline .url, .attachment => |s| allocator.free(s),
            }
        }

        pub fn jsonStringify(self: ImageRef, jw: anytype) !void {
            switch (self) {
                .url => |s| try jw.write(s),
                .attachment => |s| try jw.print("\"attachment://{s}\"", .{s}),
            }
        }
    };

    allocator: std.mem.Allocator,

    title: std.Io.Writer.Allocating,
    description: std.Io.Writer.Allocating,

    url: []const u8 = &.{},

    timestamp: ?i64 = null,
    color: ?Color = null,

    footer_text: std.Io.Writer.Allocating,
    footer_icon: ?ImageRef = null,

    image: ?ImageRef = null,
    thumbnail: ?ImageRef = null,
    video_url: []const u8 = &.{},

    author_name: []const u8 = &.{},
    author_url: []const u8 = &.{},
    author_icon: ?ImageRef = null,

    fields: std.ArrayListUnmanaged(FieldWriter) = .{},

    pub fn init(allocator: std.mem.Allocator) EmbedBuilder {
        return .{
            .allocator = allocator,
            .title = .init(allocator),
            .description = .init(allocator),
            .footer_text = .init(allocator),
        };
    }

    pub fn deinit(self: EmbedBuilder) void {
        for (self.fields.items) |field| {
            field.deinit();
        }
        self.fields.deinit(self.allocator);
    }

    pub fn addOwnedField(self: *EmbedBuilder, field_builder: FieldWriter) !void {
        try self.fields.append(self.allocator, field_builder);
    }

    pub fn newField(self: *EmbedBuilder) !*FieldWriter {
        const builder = try self.fields.addOne(self.allocator);
        builder.* = .init(self.allocator);
        return builder;
    }

    pub fn jsonStringify(self: EmbedBuilder, jw: anytype) !void {
        try jw.beginObject();
        {
            try jw.objectField("type");
            try jw.write("rich");
        }
        if (self.title.writer.buffered().len > 0) {
            try jw.objectField("title");
            try jw.write(self.title.writer.buffered());
        }
        if (self.description.writer.buffered().len > 0) {
            try jw.objectField("description");
            try jw.write(self.description.writer.buffered());
        }
        if (self.url.len > 0) {
            try jw.objectField("url");
            try jw.write(self.url);
        }
        if (self.timestamp) |timestamp| {
            const dt = datetime.Datetime.fromTimestamp(timestamp);
            var iso_buf: [64]u8 = undefined;
            const iso_str = dt.formatISO8601Buf(&iso_buf, false) catch unreachable;
            try jw.objectField("timestamp");
            try jw.write(iso_str);
        }
        if (self.color) |color| {
            try jw.objectField("color");
            try jw.write(color);
        }
        if (self.footer_text.writer.buffered().len > 0 or self.footer_icon != null) {
            try jw.objectField("footer");
            try jw.beginObject();
            {
                try jw.objectField("text");
                try jw.write(self.footer_text.writer.buffered());
            }
            if (self.footer_icon) |ref| {
                try jw.objectField("icon_url");
                try jw.write(ref);
            }
            try jw.endObject();
        }
        if (self.image) |ref| {
            try jw.objectField("image");
            try jw.beginObject();
            {
                try jw.objectField("url");
                try jw.write(ref);
            }
            try jw.endObject();
        }
        if (self.thumbnail) |ref| {
            try jw.objectField("thumbnail");
            try jw.beginObject();
            {
                try jw.objectField("url");
                try jw.write(ref);
            }
            try jw.endObject();
        }
        if (self.video_url.len > 0) {
            try jw.objectField("video");
            try jw.beginObject();
            {
                try jw.objectField("url");
                try jw.write(self.video_url);
            }
            try jw.endObject();
        }
        if (self.author_name.len > 0 or self.author_url.len > 0 or self.author_icon != null) {
            try jw.objectField("author");
            try jw.beginObject();
            {
                try jw.objectField("name");
                try jw.write(self.author_name);
            }
            if (self.author_url.len > 0) {
                try jw.objectField("url");
                try jw.write(self.author_url);
            }
            if (self.author_icon) |ref| {
                try jw.objectField("icon_url");
                try jw.write(ref);
            }
            try jw.endObject();
        }
        {
            try jw.objectField("fields");
            try jw.beginArray();
            for (self.fields.items) |field| {
                try jw.write(field);
            }
            try jw.endArray();
        }
        try jw.endObject();
    }
};

pub const ComponentBuilder = union(Interaction.ComponentType) {
    pub const Layout = struct {
        allocator: std.mem.Allocator,
        components: std.ArrayListUnmanaged(ComponentBuilder) = .empty,

        pub fn init(allocator: std.mem.Allocator) Layout {
            return .{
                .allocator = allocator,
            };
        }

        pub fn deinit(self: Layout) void {
            for (self.components.items) |component| {
                component.deinit();
            }
            self.components.deinit(self.allocator);
        }

        pub fn jsonStringify(self: Layout, jw: anytype) !void {
            try jw.beginArray();
            for (self.components.items) |component| {
                try jw.write(component);
            }
            try jw.endArray();
        }

        pub fn addButton(self: *Layout) !*Button {
            const button = try self.components.addOne(self.allocator);
            button.* = .{ .button = .init(self.allocator) };
            return &button.button;
        }
    };

    pub const ActionRow = struct {
        layout: Layout,

        pub fn init(allocator: std.mem.Allocator) ActionRow {
            return .{
                .layout = .init(allocator),
            };
        }

        pub fn deinit(self: ActionRow) void {
            self.layout.deinit();
        }

        pub fn jsonStringify(self: ActionRow, jw: anytype) !void {
            try jw.objectField("components");
            try jw.write(self.layout);
        }
    };

    pub const Button = struct {
        pub const Style = enum(i32) {
            primary = 1,
            secondary,
            success,
            danger,
            link,
            premium,
        };

        pub const EmojiPartial = struct {
            id: Snowflake,
            name: []const u8,
            animated: bool,
        };

        allocator: std.mem.Allocator,

        style: Style = .primary,
        label: std.Io.Writer.Allocating,
        emoji: ?EmojiPartial = null,
        custom_id: ?[]const u8 = null,
        sku: ?Snowflake = null,
        url: ?[]const u8 = null,
        disabled: bool = false,

        pub fn init(allocator: std.mem.Allocator) Button {
            return .{
                .allocator = allocator,
                .label = .init(allocator),
            };
        }

        pub fn deinit(self: Button) void {
            self.label.deinit();
        }

        pub fn jsonStringify(self: Button, jw: anytype) !void {
            try jw.objectField("style");
            try jw.write(@intFromEnum(self.style));

            if (self.label.writer.buffered().len > 0) {
                try jw.objectField("label");
                try jw.write(self.label.writer.buffered());
            }

            if (self.emoji) |emoji| {
                try jw.objectField("emoji");
                try jw.write(emoji);
            }

            switch (self.style) {
                .primary, .secondary, .success, .danger => {
                    const custom_id = self.custom_id orelse @panic("No custom ID provided for standard button");
                    try jw.objectField("custom_id");
                    try jw.write(custom_id);
                },
                .link => {
                    try jw.objectField("url");
                    const url = self.url orelse @panic("No URL provided for button of style 'link'");
                    try jw.write(url);
                },
                .premium => {
                    try jw.objectField("sku");
                    const sku = self.sku orelse @panic("No SKU provided for button of style 'premium'");
                    try jw.write(sku);
                },
            }

            try jw.objectField("disabled");
            try jw.write(self.disabled);
        }
    };

    pub const StringSelect = struct {};
    pub const TextInput = struct {};
    pub const UserSelect = struct {};
    pub const RoleSelect = struct {};
    pub const MentionableSelect = struct {};
    pub const ChannelSelect = struct {};
    pub const Section = struct {};
    pub const TextDisplay = struct {};
    pub const Thumbnail = struct {};
    pub const MediaGallery = struct {};
    pub const File = struct {};
    pub const Separator = struct {};
    pub const Container = struct {};
    pub const Label = struct {};
    pub const FileUpload = struct {};

    action_row: ActionRow,
    button: Button,
    string_select: StringSelect,
    text_input: TextInput,
    user_select: UserSelect,
    role_select: RoleSelect,
    mentionable_select: MentionableSelect,
    channel_select: ChannelSelect,
    section: Section,
    text_display: TextDisplay,
    thumbnail: Thumbnail,
    media_gallery: MediaGallery,
    file: File,
    separator: Separator,
    container: Container,
    label: Label,
    file_upload: FileUpload,

    pub fn deinit(self: ComponentBuilder) void {
        switch (self) {
            inline else => |inner| if (@hasDecl(@TypeOf(inner), "deinit")) inner.deinit(),
        }
    }

    pub fn jsonStringify(self: ComponentBuilder, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("type");
        try jw.write(@intFromEnum(self));
        switch (self) {
            inline else => |inner| try jw.write(inner),
        }
        try jw.endObject();
    }
};

allocator: std.mem.Allocator,

content: std.Io.Writer.Allocating,
embeds: std.ArrayListUnmanaged(EmbedBuilder) = .empty,
components: std.ArrayListUnmanaged(ComponentBuilder) = .empty,

pub fn init(allocator: std.mem.Allocator) MessageBuilder {
    return .{
        .allocator = allocator,
        .content = .init(allocator),
    };
}

pub fn simple(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !MessageBuilder {
    var builder: MessageBuilder = .init(allocator);
    errdefer builder.deinit();

    try builder.content.writer.print(fmt, args);

    return builder;
}

pub fn deinit(self: *MessageBuilder) void {
    self.embeds.deinit(self.allocator);
    self.content.deinit();
}

pub fn addOwnedEmbed(self: *MessageBuilder, embed_builder: EmbedBuilder) !void {
    try self.embeds.append(self.allocator, embed_builder);
}

pub fn newEmbed(self: *MessageBuilder) !*EmbedBuilder {
    const builder = try self.embeds.addOne(self.allocator);
    builder.* = .init(self.allocator);
    return builder;
}

pub fn addActionRow(self: *MessageBuilder) !*ComponentBuilder.ActionRow {
    const component = try self.components.addOne(self.allocator);
    component.* = .{
        .action_row = .init(self.allocator),
    };
    return &component.action_row;
}

pub fn jsonStringifyInner(self: MessageBuilder, jw: anytype) !void {
    var flags: Message.Flags = .{};
    _ = &flags;
    {
        try jw.objectField("content");
        try jw.write(self.content.writer.buffered());
    }
    {
        try jw.objectField("embeds");
        try jw.beginArray();
        for (self.embeds.items) |embed_builder| {
            try jw.write(embed_builder);
        }
        try jw.endArray();
    }
    if (self.components.items.len > 0) {
        // flags.is_components_v2 = true;
        {
            try jw.objectField("components");
            try jw.beginArray();
            for (self.components.items) |component_builder| {
                try jw.write(component_builder);
            }
            try jw.endArray();
            // {

            //     try jw.beginObject();
            //     {
            //         try jw.objectField("type");
            //         try jw.write(1);
            //         try jw.objectField("components");
            //         try jw.beginArray();
            //         {
            //             try jw.beginObject();
            //             {
            //                 try jw.objectField("type");
            //                 try jw.write(2);
            //                 try jw.objectField("style");
            //                 try jw.write(4);
            //                 try jw.objectField("label");
            //                 try jw.write("Kill Barney");
            //                 try jw.objectField("custom_id");
            //                 try jw.write("a");
            //             }
            //             try jw.endObject();
            //         }
            //         try jw.endArray();
            //     }
            //     try jw.endObject();
            // }
        }
    }
    try jw.objectField("flags");
    try jw.write(@as(i32, @bitCast(flags)));
}

pub fn jsonStringify(self: MessageBuilder, jw: anytype) !void {
    try jw.beginObject();
    try self.jsonStringifyInner(jw);
    try jw.endObject();
}
