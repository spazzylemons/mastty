const RestClient = @import("RestClient.zig");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var rest = try RestClient.init(allocator, "mastodon.social");
    defer rest.deinit();

    var foo = try rest.get("/api/v1/timelines/public?limit=2");
    defer foo.deinit();

    std.log.info("{}", .{foo.root});
}
