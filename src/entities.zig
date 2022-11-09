const std = @import("std");

fn jsonFree(comptime T: type) type {
    return struct {
        pub fn deinit(self: T, allocator: std.mem.Allocator) void {
            std.json.parseFree(T, self, .{ .allocator = allocator });
        }
    };
}

pub const Application = struct {
    pub usingnamespace jsonFree(@This());

    name: []const u8,
    website: ?[]const u8 = null,
    vapid_key: []const u8,
    client_id: []const u8,
    client_secret: []const u8,
};

pub const Token = struct {
    pub usingnamespace jsonFree(@This());

    access_token: []const u8,
    token_type: []const u8,
    scope: []const u8,
    created_at: i64,
};
