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
/// Our authorization key, borrowed reference from config file.
authorization: ?[]const u8 = null,

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

fn request(self: *RestClient, method: []const u8, url: []const u8, body: ?[]const u8) ![]const u8 {
    const ssl = try self.getSsl();
    errdefer self.invalidateSsl();

    var buffer: [4096]u8 = undefined;
    var client = hzzp.base.client.create(&buffer, ssl.reader(), ssl.writer());
    try client.writeStatusLine(method, url);
    try client.writeHeaderValue("Host", self.instance);
    if (self.authorization) |auth| {
        try client.writeHeaderFormat("Authorization", "Bearer {s}", .{auth});
    }
    if (body) |b| {
        try client.writeHeaderValue("Content-Type", "application/json");
        try client.writeHeaderFormat("Content-Length", "{}", .{b.len});
    }
    try client.finishHeaders();
    if (body) |b| {
        try client.writePayload(b);
    }

    var payload_buffer = std.ArrayList(u8).init(self.allocator);
    defer payload_buffer.deinit();

    while (try client.next()) |event| {
        switch (event) {
            .status => |status| {
                if (status.code != 200) {
                    try std.io.getStdErr().writer().print("HTTP status code {}\n", .{status.code});
                    return error.StatusCode;
                }
            },

            .payload => |payload| {
                try payload_buffer.writer().writeAll(payload.data);
            },

            else => {},
        }
    }

    return payload_buffer.toOwnedSlice();
}

/// Make a GET request to a URL.
pub fn get(self: *RestClient, comptime T: type, url: []const u8) !T {
    var response = try self.request("GET", url, null);
    defer self.allocator.free(response);

    var stream = std.json.TokenStream.init(response);
    return try std.json.parse(T, &stream, .{
        .allocator = self.allocator,
        .ignore_unknown_fields = true,
    });
}

/// Make a POST request to a URL.
pub fn post(self: *RestClient, comptime T: type, url: []const u8, value: anytype) !T {
    var request_buffer = std.ArrayList(u8).init(self.allocator);
    defer request_buffer.deinit();

    try std.json.stringify(value, .{}, request_buffer.writer());

    var response = try self.request("POST", url, request_buffer.items);
    defer self.allocator.free(response);

    var stream = std.json.TokenStream.init(response);
    return try std.json.parse(T, &stream, .{
        .allocator = self.allocator,
        .ignore_unknown_fields = true,
    });
}
