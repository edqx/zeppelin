const std = @import("std");
const Authentication = @import("authentication.zig").Authentication;

const Rest = @This();

pub const Request = struct {
    server_header_buffer: []u8,
    allocator: std.mem.Allocator,

    authorization_header: ?[]const u8,
    authentication: *Authentication,
    http_request: std.http.Client.Request,

    pub fn deinit(self: *Request) void {
        self.http_request.deinit();
        if (self.authorization_header) |authorization_header| self.allocator.free(authorization_header);
        self.allocator.free(self.server_header_buffer);
    }

    pub fn writer(self: *Request) std.http.Client.Request.Writer {
        return self.http_request.writer();
    }

    pub fn begin(self: *Request, content_type: []const u8) !void {
        self.authorization_header = try std.fmt.allocPrint(self.allocator, "Bot {s}", .{self.authentication.resolve()});
        errdefer if (self.authorization_header) |authorization_header| self.allocator.free(authorization_header);

        self.http_request.headers = .{
            .authorization = .{ .override = self.authorization_header.? },
            .content_type = .{ .override = content_type },
        };
        try self.http_request.send();
    }

    pub fn fetchJson(self: *Request, allocator: std.mem.Allocator, comptime ResponseData: type) !ResponseData {
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

pub fn create(self: *Rest, method: std.http.Method, uri: std.Uri) !Request {
    const server_header_buffer = try self.allocator.alloc(u8, 2048);
    errdefer self.allocator.free(server_header_buffer);

    var req = try self.http_client.open(method, uri, .{
        .server_header_buffer = server_header_buffer,
    });
    req.transfer_encoding = .chunked;

    return .{
        .server_header_buffer = server_header_buffer,
        .allocator = self.allocator,
        .authorization_header = null,
        .authentication = &self.authentication,
        .http_request = req,
    };
}
