const std = @import("std");
const wardrobe = @import("wardrobe");

const log = @import("log.zig").zeppelin;

const Authentication = @import("authentication.zig").Authentication;

const Rest = @This();

pub fn MultiWriter(comptime Writers: type) type {
    comptime var ErrSet = error{};
    inline for (@typeInfo(Writers).@"struct".fields) |field| {
        const StreamType = field.type;
        ErrSet = ErrSet || StreamType.Error;
    }

    return struct {
        const Self = @This();

        streams: Writers,

        pub const Error = ErrSet;
        pub const Writer = std.io.Writer(Self, Error, write);

        pub fn writer(self: Self) Writer {
            return .{ .context = self };
        }

        pub fn write(self: Self, bytes: []const u8) Error!usize {
            inline for (self.streams) |stream|
                try stream.writeAll(bytes);
            return bytes.len;
        }
    };
}

pub fn multiWriter(streams: anytype) MultiWriter(@TypeOf(streams)) {
    return .{ .streams = streams };
}

pub const Request = struct {
    pub const HttpWriter = std.http.Client.Request.Writer;
    pub const FormDataWriter = wardrobe.WriteStream(HttpWriter);

    pub const Writer = struct {
        request: *Request,
        http_writer: HttpWriter,
        adapter: HttpWriter.Adapter,

        pub fn jsonWriter(self: *Writer) !std.json.Stringify {
            try self.request.setJson();
            return .{ .writer = &self.adapter.new_interface };
        }

        pub fn formDataWriter(self: *Writer) !FormDataWriter {
            const boundary = try self.request.setFormData();
            return wardrobe.writeStream(boundary, self.http_writer);
        }
    };

    arena: std.heap.ArenaAllocator,
    random: std.Random,
    http_request: std.http.Client.Request,

    sent: bool = false,

    pub fn deinit(self: *Request) void {
        self.http_request.deinit();
        self.arena.deinit();
    }

    pub fn writer(self: *Request) Writer {
        return .{
            .request = self,
            .http_writer = self.http_request.writer(),
            .adapter = self.http_request.writer().adaptToNewApi(),
        };
    }

    pub fn setJson(self: *Request) !void {
        log.debug("- Started JSON request body", .{});

        self.http_request.headers.content_type = .{ .override = "application/json" };

        try self.http_request.send();
        self.sent = true;
    }

    pub fn setFormData(self: *Request) !wardrobe.Boundary {
        const allocator = self.arena.allocator();

        log.debug("- Started form data request body", .{});

        const boundary: wardrobe.Boundary = .entropy("ZeppelinBoundary", self.random);

        const content_type_header = try allocator.dupe(u8, boundary.contentType());
        errdefer allocator.free(content_type_header);

        self.http_request.headers.content_type = .{ .override = content_type_header };

        try self.http_request.send();
        self.sent = true;

        return boundary;
    }

    pub fn fetch(self: *Request) !void {
        if (!self.sent) try self.http_request.send();
        self.sent = true;

        log.debug("- Request finished", .{});

        try self.http_request.finish();
        try self.http_request.wait();

        log.debug("- Response received, code: {s} {s} ({})", .{ @tagName(self.status().class()), @tagName(self.status()), @intFromEnum(self.status()) });
    }

    pub fn status(self: *Request) std.http.Status {
        return self.http_request.response.status;
    }

    pub fn fetchJson(self: *Request, comptime ResponseData: type) !ResponseData {
        try self.fetch();
        switch (self.status().class()) {
            .success => return try self.readJson(ResponseData),
            .client_error => {
                const body = try self.http_request.reader().readAllAlloc(self.arena.allocator(), std.math.maxInt(usize));
                defer self.arena.allocator().free(body);

                log.err("Request error: {s}", .{body});
                return error.RequestError;
            },
            else => return error.ResponseError,
        }
    }

    pub fn readJson(self: *Request, comptime ResponseData: type) !ResponseData {
        const allocator = self.arena.allocator();

        var buffer: [4096]u8 = undefined;
        var new_reader = self.http_request.reader().adaptToNewApi(&buffer);

        var json_reader: std.json.Reader = .init(allocator, &new_reader.new_interface);
        defer json_reader.deinit();

        return try std.json.parseFromTokenSourceLeaky(ResponseData, allocator, &json_reader, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        });
    }
};

allocator: std.mem.Allocator,
authentication: Authentication,
http_client: std.http.Client,

default_prng: std.Random.DefaultPrng,

pub fn init(allocator: std.mem.Allocator, authentication: Authentication) Rest {
    return .{
        .allocator = allocator,
        .authentication = authentication,
        .http_client = .{
            .allocator = allocator,
        },
        .default_prng = .init(@intCast(std.time.microTimestamp())),
    };
}

pub fn deinit(self: *Rest) void {
    self.http_client.deinit();
}

pub fn create(
    self: *Rest,
    method: std.http.Method,
    comptime endpoint: []const u8,
    parameters: anytype,
) !Request {
    var arena: std.heap.ArenaAllocator = .init(self.allocator);
    errdefer arena.deinit();

    const allocator = arena.allocator();

    const server_header_buffer = try allocator.alloc(u8, 2048);
    errdefer allocator.free(server_header_buffer);

    const formatted_uri = try std.fmt.allocPrint(allocator, endpoint, parameters);
    errdefer allocator.free(formatted_uri);

    var req = try self.http_client.open(method, try std.Uri.parse(formatted_uri), .{
        .server_header_buffer = server_header_buffer,
    });
    if (method.requestHasBody()) {
        req.transfer_encoding = .chunked;
    }

    const authorization_header = try std.fmt.allocPrint(allocator, "Bot {s}", .{self.authentication.resolve()});
    errdefer allocator.free(authorization_header);

    req.headers.authorization = .{ .override = authorization_header };

    log.info("Request: {s} @ {s}", .{ @tagName(method), formatted_uri });

    return .{
        .arena = arena,
        .random = self.default_prng.random(),
        .http_request = req,
    };
}
