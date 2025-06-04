const std = @import("std");
const datetime = @import("datetime").datetime;

const Snowflake = @import("snowflake.zig").Snowflake;

const Color = @import("structures/Message.zig").Color;

const MessageBuilder = @This();

pub const Mention = union(enum) {
    pub const Named = struct {
        name: []const u8,
        id: Snowflake,

        pub fn format(self: Named, comptime _: []const u8, _: std.fmt.FormatOptions, writer2: anytype) !void {
            try writer2.print("{s}:{}", .{ self.name, self.id });
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

        pub fn format(self: Timestamp, comptime _: []const u8, _: std.fmt.FormatOptions, writer2: anytype) !void {
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

    pub fn format(self: Mention, comptime _: []const u8, _: std.fmt.FormatOptions, writer2: anytype) !void {
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
            inline else => |e| try writer2.print("{}", .{e}),
        }
        try writer2.print(">", .{});
    }
};

pub const FieldBuilder = struct {
    allocator: std.mem.Allocator,

    _name: std.ArrayListUnmanaged(u8) = .empty,
    _value: std.ArrayListUnmanaged(u8) = .empty,
    _inline: bool = false,

    pub fn deinit(self: FieldBuilder) void {
        _ = self;
    }

    pub fn titleWriter(self: *FieldBuilder) std.ArrayListUnmanaged(u8).Writer {
        return self._name.writer(self.allocator);
    }

    pub fn title(self: *FieldBuilder, comptime fmt: []const u8, args: anytype) !void {
        try self.titleWriter().print(fmt, args);
    }

    pub fn bodyWriter(self: *FieldBuilder) std.ArrayListUnmanaged(u8).Writer {
        return self._value.writer(self.allocator);
    }

    pub fn body(self: *FieldBuilder, comptime fmt: []const u8, args: anytype) !void {
        try self.bodyWriter().print(fmt, args);
    }

    pub fn displayInline(self: *FieldBuilder) void {
        self._inline = true;
    }

    pub fn jsonStringify(self: FieldBuilder, jw: anytype) !void {
        try jw.beginObject();
        {
            try jw.objectField("name");
            try jw.write(self._name.items);
        }
        {
            try jw.objectField("value");
            try jw.write(self._value.items);
        }
        if (self._inline) {
            try jw.objectField("inline");
            try jw.write(self._inline);
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

    _title: std.ArrayListUnmanaged(u8) = .empty,
    _description: std.ArrayListUnmanaged(u8) = .empty,

    _url: []const u8 = &.{},

    _timestamp: ?i64 = null,
    _color: ?Color = null,

    _footer_text: std.ArrayListUnmanaged(u8) = .empty,
    _footer_icon_ref: ?ImageRef = null,

    _image_ref: ?ImageRef = null,
    _thumbnail_ref: ?ImageRef = null,
    _video_url: []const u8 = &.{},

    _author_name: []const u8 = &.{},
    _author_url: []const u8 = &.{},
    _author_icon_ref: ?ImageRef = null,

    _fields: std.BoundedArray(FieldBuilder, 25) = .{},

    pub fn deinit(self: EmbedBuilder) void {
        var s = self; // hack to deinit ArrayList without taking pointer

        for (s._fields.slice()) |field_builder| {
            field_builder.deinit();
        }

        if (s._author_icon_ref) |ref| ref.deinit(s.allocator);
        s.allocator.free(s._author_url);
        s.allocator.free(s._author_name);

        s.allocator.free(s._video_url);
        if (s._thumbnail_ref) |ref| ref.deinit(s.allocator);
        if (s._image_ref) |ref| ref.deinit(s.allocator);

        if (s._footer_icon_ref) |ref| ref.deinit(s.allocator);
        s._footer_text.deinit(s.allocator);

        s.allocator.free(s._url);

        s._description.deinit(s.allocator);
        s._title.deinit(s.allocator);
    }

    pub fn titleWriter(self: *EmbedBuilder) std.ArrayListUnmanaged(u8).Writer {
        return self._title.writer(self.allocator);
    }

    pub fn title(self: *EmbedBuilder, comptime fmt: []const u8, args: anytype) !void {
        try self.titleWriter().print(fmt, args);
    }

    pub fn descriptionWriter(self: *EmbedBuilder) std.ArrayListUnmanaged(u8).Writer {
        return self._description.writer(self.allocator);
    }

    pub fn description(self: *EmbedBuilder, comptime fmt: []const u8, args: anytype) !void {
        try self.descriptionWriter().print(fmt, args);
    }

    pub fn url(self: *EmbedBuilder, _url: []const u8) !void {
        self.allocator.free(self._url);
        self._url = try self.allocator.dupe(u8, _url);
    }

    pub fn timestamp(self: *EmbedBuilder, _timestamp: i64) void {
        self._timestamp = _timestamp;
    }

    pub fn color(self: *EmbedBuilder, _color: Color) void {
        self._color = _color;
    }

    pub fn footerWriter(self: *EmbedBuilder) std.ArrayListUnmanaged(u8).Writer {
        return self._footer_text.writer(self.allocator);
    }

    pub fn footerIcon(self: *EmbedBuilder, icon_ref: ImageRef) !void {
        self._footer_icon_ref.deinit(self.allocator);
        self._footer_icon_ref = try icon_ref.dupe(self.allocator);
    }

    pub fn footer(self: *EmbedBuilder, comptime fmt: []const u8, args: anytype, icon_ref: ?ImageRef) !void {
        try self.footerWriter().print(fmt, args);
        if (icon_ref) |ref| try self.footerIcon(ref);
    }

    pub fn image(self: *EmbedBuilder, image_ref: ImageRef) !void {
        self._image_ref.deinit(self.allocator);
        self._image_ref = try image_ref.dupe(self.allocator);
    }

    pub fn thumbnail(self: *EmbedBuilder, image_ref: ImageRef) !void {
        self._thumbnail_ref.deinit(self.allocator);
        self._thumbnail_ref = try image_ref.dupe(self.allocator);
    }

    pub fn video(self: *EmbedBuilder, video_url: []const u8) !void {
        self.allocator.free(self._video_url);
        self._video_url = try self.allocator.dupe(u8, video_url);
    }

    pub fn author(self: *EmbedBuilder, name: []const u8, author_url: ?[]const u8, icon_ref: ?ImageRef) !void {
        self.allocator.free(self._author_name);
        self._author_name = try self.allocator.dupe(u8, name);
        if (author_url) |s| self._author_url = try self.allocator.dupe(u8, s);
        if (icon_ref) |ref| self._author_icon_ref = try ref.dupe(self.allocator);
    }

    pub fn addField(self: *EmbedBuilder, field_builder: FieldBuilder) !void {
        try self._fields.append(field_builder);
    }

    pub fn field(self: *EmbedBuilder) !*FieldBuilder {
        const builder = try self._fields.addOne();
        builder.* = .{ .allocator = self.allocator };
        return builder;
    }

    pub fn jsonStringify(self: EmbedBuilder, jw: anytype) !void {
        try jw.beginObject();
        {
            try jw.objectField("type");
            try jw.write("rich");
        }
        if (self._title.items.len > 0) {
            try jw.objectField("title");
            try jw.write(self._title.items);
        }
        if (self._description.items.len > 0) {
            try jw.objectField("description");
            try jw.write(self._description.items);
        }
        if (self._url.len > 0) {
            try jw.objectField("url");
            try jw.write(self._url);
        }
        if (self._timestamp) |_timestamp| {
            const dt = datetime.Datetime.fromTimestamp(_timestamp);
            var iso_buf: [64]u8 = undefined;
            const iso_str = dt.formatISO8601Buf(&iso_buf, false) catch unreachable;
            try jw.objectField("timestamp");
            try jw.write(iso_str);
        }
        if (self._color) |_color| {
            try jw.objectField("color");
            try jw.write(_color);
        }
        if (self._footer_text.items.len > 0 or self._footer_icon_ref != null) {
            try jw.objectField("footer");
            try jw.beginObject();
            {
                try jw.objectField("text");
                try jw.write(self._footer_text.items);
            }
            if (self._footer_icon_ref) |ref| {
                try jw.objectField("icon_url");
                try jw.write(ref);
            }
            try jw.endObject();
        }
        if (self._image_ref) |ref| {
            try jw.objectField("image");
            try jw.beginObject();
            {
                try jw.objectField("url");
                try jw.write(ref);
            }
            try jw.endObject();
        }
        if (self._thumbnail_ref) |ref| {
            try jw.objectField("thumbnail");
            try jw.beginObject();
            {
                try jw.objectField("url");
                try jw.write(ref);
            }
            try jw.endObject();
        }
        if (self._video_url.len > 0) {
            try jw.objectField("video");
            try jw.beginObject();
            {
                try jw.objectField("url");
                try jw.write(self._video_url);
            }
            try jw.endObject();
        }
        if (self._author_name.len > 0 or self._author_url.len > 0 or self._author_icon_ref != null) {
            try jw.objectField("author");
            try jw.beginObject();
            {
                try jw.objectField("name");
                try jw.write(self._author_name);
            }
            if (self._author_url.len > 0) {
                try jw.objectField("url");
                try jw.write(self._author_url);
            }
            if (self._author_icon_ref) |ref| {
                try jw.objectField("icon_url");
                try jw.write(ref);
            }
            try jw.endObject();
        }
        {
            try jw.objectField("fields");
            try jw.beginArray();
            for (self._fields.slice()) |field_builder| {
                try jw.write(field_builder);
            }
            try jw.endArray();
        }
        try jw.endObject();
    }
};

allocator: std.mem.Allocator,

_content: std.ArrayListUnmanaged(u8) = .empty,
_embeds: std.BoundedArray(EmbedBuilder, 10) = .{},

pub fn simple(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !MessageBuilder {
    var builder: MessageBuilder = .{ .allocator = allocator };
    errdefer builder.deinit();

    try builder.content(fmt, args);

    return builder;
}

pub fn deinit(self: MessageBuilder) void {
    var s = self; // hack to deinit ArrayList without taking pointer

    for (s._embeds.slice()) |embed_builder| {
        embed_builder.deinit();
    }

    s._content.deinit(s.allocator);

    s._content = .empty;
    s._embeds = .{};
}

pub fn contentWriter(self: *MessageBuilder) std.ArrayListUnmanaged(u8).Writer {
    return self._content.writer(self.allocator);
}

pub fn content(self: *MessageBuilder, comptime fmt: []const u8, args: anytype) !void {
    try self.contentWriter().print(fmt, args);
}

pub fn addEmbed(self: *MessageBuilder, embed_builder: EmbedBuilder) !void {
    try self._embeds.append(embed_builder);
}

pub fn embed(self: *MessageBuilder) !*EmbedBuilder {
    const builder = self._embeds.addOne() catch |e| switch (e) {
        error.Overflow => return error.TooManyEmbeds,
        else => return e,
    };
    builder.* = .{ .allocator = self.allocator };
    return builder;
}

pub fn jsonStringify(self: MessageBuilder, jw: anytype) !void {
    try jw.beginObject();
    {
        try jw.objectField("content");
        try jw.write(self._content.items);
    }
    {
        try jw.objectField("embeds");
        try jw.beginArray();
        for (self._embeds.slice()) |embed_builder| {
            try jw.write(embed_builder);
        }
        try jw.endArray();
    }
    try jw.endObject();
}
