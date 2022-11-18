const std = @import("std");
const util = @import("util.zig");

const LineWrapper = @This();

/// The word currently buffered.
buffer: std.ArrayList(u8),
/// The position to insert the next word.
position: usize = 0,
/// The width of the lines.
width: usize,
/// The lines generated.
lines: std.ArrayList([]u8),
/// The current line.
current: std.ArrayList(u8),

pub fn init(allocator: std.mem.Allocator, width: usize) LineWrapper {
    return .{
        .buffer = std.ArrayList(u8).init(allocator),
        .width = width,
        .lines = std.ArrayList([]u8).init(allocator),
        .current = std.ArrayList(u8).init(allocator),
    };
}

pub fn deinit(self: LineWrapper) void {
    for (self.lines.items) |line| {
        self.lines.allocator.free(line);
    }
    self.lines.deinit();
    self.buffer.deinit();
    self.current.deinit();
}

fn addLine(self: *LineWrapper) !void {
    try self.lines.ensureUnusedCapacity(1);
    self.lines.appendAssumeCapacity(self.current.toOwnedSlice());
    self.position = 0;
}

fn commitWord(self: *LineWrapper) !void {
    // if the buffer is empty, do nothing
    if (self.buffer.items.len == 0) return;
    // is there enough room to insert the line?
    const word_width = util.stringWidth(self.buffer.items);
    var test_pos = self.position;
    if (self.position > 0) {
        // account for space
        test_pos += 1;
    }
    if (word_width + test_pos + 1 <= self.width) {
        // put the word on the current line
        if (self.position > 0) {
            try self.current.append(' ');
            self.position += 1;
        }
        try self.current.appendSlice(self.buffer.items);
        self.buffer.clearRetainingCapacity();
        self.position += word_width;
    } else {
        // add parts to lines
        var buf = self.buffer.items;
        while (buf.len > 0) {
            try self.addLine();
            const slice = util.stringMaxWidth(buf, self.width);
            try self.current.appendSlice(slice);
            buf = buf[slice.len..];
            self.position = util.stringWidth(slice);
        }
        self.buffer.clearRetainingCapacity();
    }
}

pub fn add(self: *LineWrapper, char: u8) !void {
    if (char == ' ') {
        try self.commitWord();
    } else if (char == '\n') {
        try self.commitWord();
        try self.addLine();
    } else {
        try self.buffer.append(char);
    }
}

fn write(self: *LineWrapper, buf: []const u8) !usize {
    for (buf) |char| {
        try self.add(char);
    }
    return buf.len;
}

pub fn writer(self: *LineWrapper) std.io.Writer(*LineWrapper, @typeInfo(@typeInfo(@TypeOf(write)).Fn.return_type.?).ErrorUnion.error_set, write) {
    return .{ .context = self };
}

test {
    try util.initLocale();

    const sample = "According to all known laws of aviation, there is no way a bee should be able to fly.\nIts wings are too small to lift its fat little body off the ground.\nThe bee, of course, flies anyway, because bees don't care what humans think is impossible.\n";
    var wrapper = LineWrapper.init(std.testing.allocator, 32);
    defer wrapper.deinit();
    for (sample) |char| {
        try wrapper.add(char);
    }
    // TODO actually test
}
