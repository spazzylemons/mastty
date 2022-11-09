const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("readline/readline.h");
});
const std = @import("std");

pub fn line(allocator: std.mem.Allocator, prompt: ?[*:0]const u8) ![]const u8 {
    if (c.readline(prompt)) |l| {
        defer c.free(l);
        return try allocator.dupe(u8, std.mem.span(l));
    }
    return &.{};
}
