const hzzp = @import("hzzp");
const openssl = @import("openssl.zig");
const std = @import("std");

const RestClient = @This();

/// The allocator used by the client.
allocator: std.mem.Allocator,
/// The OpenSSL context in use.
ctx: openssl.Context,
/// The OpenSSL connection, or null if invalid.
ssl: ?openssl.SSL = null,
/// The network connection, or undefined if ssl is null.
socket: std.net.Stream = undefined,
/// An owned copy of the instance name.
instance: [:0]const u8,

pub fn init(allocator: std.mem.Allocator, instance: []const u8) !RestClient {
    const instance_copy = try allocator.dupeZ(u8, instance);
    errdefer allocator.free(instance_copy);

    const ctx = try openssl.Context.init(openssl.Method.client());
    errdefer ctx.deinit();

    return RestClient{
        .allocator = allocator,
        .ctx = ctx,
        .instance = instance_copy,
    };
}

pub fn deinit(self: RestClient) void {
    if (self.ssl) |s| {
        s.shutdown();
        s.deinit();
        self.socket.close();
    }
    self.ctx.deinit();
    self.allocator.free(self.instance);
}

/// Get the SSL instance, creating one if it does not exist.
fn getSsl(self: *RestClient) !openssl.SSL {
    // do we have one?
    if (self.ssl) |ssl| {
        return ssl;
    }
    // create an SSL instance
    const ssl = try openssl.SSL.init(self.ctx);
    errdefer ssl.deinit();
    // open a connection
    const socket = try std.net.tcpConnectToHost(self.allocator, self.instance, 443);
    errdefer socket.close();
    // setup the connection
    try ssl.setStream(socket);
    try ssl.setTLSExtHostName(self.instance);
    try ssl.connect();
    // all good
    self.ssl = ssl;
    self.socket = socket;
    return ssl;
}

/// Invalidate the SSL instance, if one exists.
fn invalidateSsl(self: *RestClient) void {
    if (self.ssl) |ssl| {
        // don't call shutdown - the connection's in an invalid state
        ssl.deinit();
        self.socket.close();
        self.ssl = null;
    }
}

/// Make a GET request to a URL.
pub fn get(self: *RestClient, url: []const u8) !std.json.ValueTree {
    const ssl = try self.getSsl();
    errdefer self.invalidateSsl();

    var buffer: [4096]u8 = undefined;
    var client = hzzp.base.client.create(&buffer, ssl.reader(), ssl.writer());
    try client.writeStatusLine("GET", url);
    try client.writeHeaderValue("Host", self.instance);
    try client.finishHeaders();

    var payload_buffer = std.ArrayList(u8).init(self.allocator);
    defer payload_buffer.deinit();

    while (try client.next()) |event| {
        switch (event) {
            .status => |status| {
                if (status.code != 200) {
                    return error.StatusCode;
                }
            },

            .payload => |payload| {
                try payload_buffer.writer().writeAll(payload.data);
            },

            else => {},
        }
    }

    var parser = std.json.Parser.init(self.allocator, true);
    defer parser.deinit();

    return try parser.parse(payload_buffer.items);
}
