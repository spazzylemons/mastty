const std = @import("std");

fn HtmlRenderer(comptime Writer: type) type {
    return struct {
        const Self = @This();

        writer: Writer,

        remaining_input_ptr: [*]const u8,
        remaining_input_len: usize,

        capture: ?[*]const u8 = null,

        fn next(self: *Self) ?[*]const u8 {
            if (self.remaining_input_len > 0) {
                const result = self.remaining_input_ptr;
                self.remaining_input_ptr += 1;
                self.remaining_input_len -= 1;
                return result;
            }
            return null;
        }

        fn getCapture(self: *Self) ?[]const u8 {
            if (self.capture) |capture| {
                self.capture = null;
                const len = @ptrToInt(self.remaining_input_ptr) - @ptrToInt(capture);
                return capture[0..len];
            }
            return null;
        }

        fn writeCodepointEntity(self: Self, name: []const u8) !void {
            if (!std.mem.startsWith(u8, name, "#")) {
                return error.NotCodepoint;
            }
            const int = try std.fmt.parseInt(u21, name[1..], 10);
            var buf: [4]u8 = undefined;
            const len = try std.unicode.utf8Encode(int, &buf);
            try self.writer.writeAll(buf[0..len]);
        }

        // TODO (?) - rendering does not trim whitespace, handwritten html won't look right
        // also this probably isn't spec compliant
        fn render(self: *Self) !void {
            while (self.next()) |ptr| {
                switch (ptr[0]) {
                    '<', '&' => {
                        if (self.capture != null) {
                            return error.HtmlError;
                        }
                        self.capture = ptr;
                    },

                    '>' => {
                        const contents = self.getCapture() orelse return error.HtmlError;
                        if (contents[0] != '<') return error.HtmlError;
                        const element_type = std.mem.sliceTo(contents[1..contents.len - 1], ' ');
                        self.capture = null;
                        if (std.mem.startsWith(u8, element_type, "/")) {
                            return;
                        } else {
                            // don't recurse if '/' at end
                            if (!std.mem.endsWith(u8, contents, "/>")) {
                                try self.render();
                            }
                            if (std.mem.eql(u8, element_type, "p")) {
                                // line break at end of <p>
                                try self.writer.writeAll("\n\n");
                            } else if (std.mem.eql(u8, element_type, "br")) {
                                // smaller line break at <br/>
                                try self.writer.writeAll("\n");
                            }
                        }
                    },

                    ';' => {
                        const contents = self.getCapture() orelse return error.HtmlError;
                        if (contents[0] != '&') return error.HtmlError;
                        const name = contents[1..contents.len - 1];
                        if (std.mem.eql(u8, name, "amp")) {
                            try self.writer.writeByte('&');
                        } else if (std.mem.eql(u8, name, "lt")) {
                            try self.writer.writeByte('<');
                        } else if (std.mem.eql(u8, name, "gt")) {
                            try self.writer.writeByte('>');
                        } else if (std.mem.eql(u8, name, "quot")) {
                            try self.writer.writeByte('"');
                        } else if (std.mem.eql(u8, name, "nbsp")) {
                            try self.writer.writeByte(' ');
                        } else {
                            // try decoding codepoint, fallback to outputting untranslated entity
                            self.writeCodepointEntity(name) catch {
                                try self.writer.writeAll(contents);
                            };
                        }
                    },

                    else => |c| {
                        if (self.capture == null) {
                            try self.writer.writeByte(c);
                        }
                    },
                }
            }
        }
    };
}

pub fn renderHtml(input: []const u8, writer: anytype) !void {
    var renderer = HtmlRenderer(@TypeOf(writer)){
        .writer = writer,
        .remaining_input_ptr = input.ptr,
        .remaining_input_len = input.len,
    };
    try renderer.render();
}

test {
    var array = std.ArrayList(u8).init(std.testing.allocator);
    defer array.deinit();

    try renderHtml("<p>foo &amp; bar</p>", array.writer());

    try std.testing.expectEqualSlices(u8, array.items,
        \\foo & bar
        \\
        \\
    );
}
