const std = @import("std");
const wardrobe = @import("wardrobe");

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
    arena: std.heap.ArenaAllocator,
    random: std.Random,
    http_request: std.http.Client.Request,

    sent: bool = false,

    // pub const Writer = MultiWriter(struct { std.fs.File.Writer, std.http.Client.Request.Writer }).Writer;
    pub const Writer = std.http.Client.Request.Writer;
    pub const JsonWriter = std.json.WriteStream(Writer, .{ .checked_to_fixed_depth = 256 });
    pub const FormDataWriter = wardrobe.WriteStream(Writer);

    pub fn deinit(self: *Request) void {
        self.http_request.deinit();
        self.arena.deinit();
    }

    pub fn writer(self: *Request) std.http.Client.Request.Writer {
        return self.http_request.writer();
    }

    pub fn beginJson(self: *Request) !JsonWriter {
        self.http_request.headers.content_type = .{ .override = "application/json" };

        try self.http_request.send();
        self.sent = true;

        // return std.json.writeStream(multiWriter(.{ std.io.getStdOut().writer(), self.writer() }).writer(), .{});
        return std.json.writeStream(self.writer(), .{});
    }

    pub fn beginFormData(self: *Request) !FormDataWriter {
        const allocator = self.arena.allocator();

        const boundary: wardrobe.Boundary = .entropy("ZeppelinBoundary", self.random);

        const content_type_header = try allocator.dupe(u8, boundary.contentType());
        errdefer allocator.free(content_type_header);

        self.http_request.headers.content_type = .{ .override = content_type_header };

        try self.http_request.send();
        self.sent = true;

        // return wardrobe.writeStream(boundary, multiWriter(.{ std.io.getStdOut().writer(), self.writer() }).writer());
        return wardrobe.writeStream(boundary, self.writer());
    }

    pub fn fetch(self: *Request) !void {
        if (!self.sent) try self.http_request.send();
        self.sent = true;

        try self.http_request.finish();
        try self.http_request.wait();
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

                std.log.info("body: {s}", .{body});
                return error.RequestError;
            },
            else => return error.ResponseError,
        }
    }

    pub fn readJson(self: *Request, comptime ResponseData: type) !ResponseData {
        const allocator = self.arena.allocator();

        var json_reader = std.json.reader(allocator, self.http_request.reader());
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

    return .{
        .arena = arena,
        .random = self.default_prng.random(),
        .http_request = req,
    };
}
