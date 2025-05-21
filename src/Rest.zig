const std = @import("std");
const wardrobe = @import("wardrobe");

const Authentication = @import("authentication.zig").Authentication;

const Rest = @This();

pub const Request = struct {
    arena: std.heap.ArenaAllocator,
    random: std.Random,
    http_request: std.http.Client.Request,

    sent: bool = false,

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

        return wardrobe.writeStream(boundary, self.writer());
    }

    pub fn fetch(self: *Request) !void {
        if (!self.sent) try self.http_request.send();
        self.sent = true;

        try self.http_request.finish();
        try self.http_request.wait();

        if (self.http_request.response.status.class() != .success) return error.RequestError;
    }

    pub fn fetchJson(self: *Request, comptime ResponseData: type) !ResponseData {
        try self.fetch();

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
