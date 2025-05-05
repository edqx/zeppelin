const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const address_list = try std.net.getAddressList(allocator, "gateway.discord.gg", 443);

    const stream = try std.net.tcpConnectToAddress(address_list.addrs[0]);
    defer stream.close();
    std.log.info("Connecting to {}\n", .{address_list.addrs[0]});

    var tls = try std.crypto.tls.Client.init(stream, .{
        .host = .no_verification,
        .ca = .no_verification,
    });

    try tls.writeAll(stream,
        \\GET / HTTP/1.1
        \\Host: gateway.discord.gg
        \\Upgrade: websocket
        \\Connection: Upgrade
        \\Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
        \\Sec-WebSocket-Version: 13
    ++ "\r\n\r\n");

    while (true) {
        var buf: [4096]u8 = undefined;
        const read_bytes = try tls.read(stream, &buf);

        if (read_bytes == 0) break;

        std.log.info("got {} bytes: {s}", .{ read_bytes, buf[0..read_bytes] });
    }
}
