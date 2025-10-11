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
    arena: std.heap.ArenaAllocator,

    random: std.Random,
    http_request: std.http.Client.Request,

    sent: bool = false,

    form_data_boundary: ?wardrobe.Boundary = null,

    pub fn deinit(self: *Request) void {
        self.http_request.deinit();
        self.arena.deinit();
    }

    pub fn sendNone(self: *Request) !void {
        std.debug.assert(!self.sent);
        defer self.sent = true;
        try self.http_request.sendBodiless();
    }

    pub fn sendEmpty(self: *Request) !void {
        std.debug.assert(!self.sent);
        defer self.sent = true;
        try self.http_request.sendBodyComplete(&.{});
    }

    pub fn sendHeadersGetWriter(self: *Request, buffer: []u8) !std.http.BodyWriter {
        std.debug.assert(!self.sent);
        defer self.sent = true;
        self.http_request.transfer_encoding = .chunked;
        return try self.http_request.sendBodyUnflushed(buffer);
    }

    pub fn setJson(self: *Request) !void {
        std.debug.assert(!self.sent);
        log.debug("- Started JSON request body", .{});

        self.http_request.headers.content_type = .{ .override = "application/json" };
    }

    pub fn setFormData(self: *Request) !wardrobe.Boundary {
        std.debug.assert(!self.sent);

        log.debug("- Started form data request body", .{});

        self.form_data_boundary = .fromEntropy("ZeppelinBoundary", self.random);
        self.http_request.headers.content_type = .{ .override = self.form_data_boundary.?.toContentType() };
        return self.form_data_boundary.?;
    }

    pub fn fetch(self: *Request) !std.http.Client.Response {
        std.debug.assert(self.sent);
        log.debug("- Request finished", .{});

        try self.http_request.connection.?.flush();

        const response = try self.http_request.receiveHead(&.{});
        log.debug("- Response received, code: {s} {s} ({})", .{ @tagName(response.head.status.class()), @tagName(response.head.status), @intFromEnum(response.head.status) });

        return response;
    }

    pub fn fetchSuccess(self: *Request) !std.http.Client.Response {
        var response = try self.fetch();
        switch (response.head.status.class()) {
            .success => return response,
            .client_error => {
                var decompress: std.http.Decompress = undefined;
                var buffer: [1024]u8 = undefined;
                var decompress_buffer: [std.compress.flate.max_window_len]u8 = undefined;
                const body_reader = response.readerDecompressing(&buffer, &decompress, &decompress_buffer);

                const body_data = try body_reader.allocRemaining(self.arena.allocator(), @enumFromInt(8 * 1024));
                defer self.arena.allocator().free(body_data);

                log.err("Request error: {} {s}", .{ response.head.status, body_data });
                return error.RequestError;
            },
            else => return error.ResponseError,
        }
    }

    pub fn fetchJson(self: *Request, comptime ResponseData: type) !ResponseData {
        var response = try self.fetchSuccess();
        return try self.readJson(&response, ResponseData);
    }

    pub fn readJson(self: *Request, response: *std.http.Client.Response, comptime ResponseData: type) !ResponseData {
        const allocator = self.arena.allocator();

        var decompress: std.http.Decompress = undefined;
        var buffer: [1024]u8 = undefined;
        var decompress_buffer: [std.compress.flate.max_window_len]u8 = undefined;
        const body_reader = response.readerDecompressing(&buffer, &decompress, &decompress_buffer);

        var json_reader: std.json.Reader = .init(allocator, body_reader);
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

    const server_header_buffer = try allocator.alloc(u8, 8192);
    errdefer allocator.free(server_header_buffer);

    const formatted_uri = try std.fmt.allocPrint(allocator, endpoint, parameters);
    errdefer allocator.free(formatted_uri);

    var req = try self.http_client.request(method, try std.Uri.parse(formatted_uri), .{});
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
