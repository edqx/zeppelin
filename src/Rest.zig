const std = @import("std");
const Authentication = @import("authentication.zig").Authentication;

const Rest = @This();

pub const Request = struct {
    pub const BodyKind = enum {
        json,
    };

    arena: std.heap.ArenaAllocator,
    http_request: std.http.Client.Request,

    pub fn deinit(self: *Request) void {
        self.http_request.deinit();
        self.arena.deinit();
    }

    pub fn writer(self: *Request) std.http.Client.Request.Writer {
        return self.http_request.writer();
    }

    pub fn begin(self: *Request, kind: BodyKind) !switch (kind) {
        .json => @TypeOf(std.json.writeStream(self.writer(), .{})),
    } {
        self.http_request.headers.content_type = .{ .override = switch (kind) {
            .json => "application/json",
        } };

        try self.http_request.send();

        return switch (kind) {
            .json => std.json.writeStream(self.writer(), .{}),
        };
    }

    pub fn fetchJson(self: *Request, comptime ResponseData: type) !ResponseData {
        const allocator = self.arena.allocator();

        try self.http_request.finish();
        try self.http_request.wait();

        if (self.http_request.response.status != .ok) return error.RequestError;

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

pub fn init(allocator: std.mem.Allocator, authentication: Authentication) Rest {
    return .{
        .allocator = allocator,
        .authentication = authentication,
        .http_client = .{
            .allocator = allocator,
        },
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
    req.transfer_encoding = .chunked;

    const authorization_header = try std.fmt.allocPrint(allocator, "Bot {s}", .{self.authentication.resolve()});
    errdefer allocator.free(authorization_header);

    req.headers.authorization = .{ .override = authorization_header };

    return .{
        .arena = arena,
        .http_request = req,
    };
}
