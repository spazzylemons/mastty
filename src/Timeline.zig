const curses = @import("curses.zig");
const entities = @import("entities.zig");
const LineWrapper = @import("LineWrapper.zig");
const std = @import("std");

const Timeline = @This();

allocator: std.mem.Allocator,
statuses: []entities.Status,
posts: []Post,

pub const Post = struct {
    status: *const entities.Status,
    lines: std.ArrayList([]u8),

    pub fn init(allocator: std.mem.Allocator, status: *const entities.Status) !Post {
        var result = Post{
            .status = status,
            .lines = std.ArrayList([]u8).init(allocator),
        };
        errdefer result.deinit();
        try result.render();
        return result;
    }

    pub fn deinit(self: Post) void {
        for (self.lines.items) |line| {
            self.lines.allocator.free(line);
        }
        self.lines.deinit();
    }

    pub fn render(self: *Post) !void {
        var wrapper = LineWrapper.init(self.lines.allocator, @intCast(usize, curses.cols()));
        defer wrapper.deinit();

        try self.status.print(wrapper.writer());

        self.deinit();
        self.lines = wrapper.lines;
        wrapper.lines = std.ArrayList([]u8).init(wrapper.lines.allocator);
    }

    pub fn display(self: Post, y: c_int, window: curses.Window) !c_int {
        var result = y;
        for (self.lines.items) |line| {
            if (window.move(result, 0)) |_| {
                window.addString(line) catch {};
            } else |_| {}
            result += 1;
        }
        return result;
    }
};

pub fn init(allocator: std.mem.Allocator, statuses: []entities.Status) !Timeline {
    var posts = std.ArrayList(Post).init(allocator);
    errdefer {
        for (posts.items) |post| {
            post.deinit();
        }
    }

    for (statuses) |*status| {
        const post = try Post.init(allocator, status);
        errdefer post.deinit();
        try posts.append(post);
    }

    return Timeline{
        .allocator = allocator,
        .statuses = statuses,
        .posts = posts.toOwnedSlice(),
    };
}

pub fn deinit(self: Timeline) void {
    for (self.posts) |post| {
        post.deinit();
    }
    self.allocator.free(self.posts);
    std.json.parseFree([]entities.Status, self.statuses, .{ .allocator = self.allocator });
}

pub fn render(self: Timeline, window: curses.Window, offset: c_int, rows: c_int) !void {
    window.erase();
    var y_pos = -offset;
    for (self.posts) |post| {
        for (post.lines.items) |line| {
            if (y_pos >= 0 and y_pos < rows) {
                try window.moveCursor(y_pos, 0);
                try window.addString(line);
            }
            y_pos += 1;
        }
    }
    window.refresh();
}
