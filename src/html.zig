const std = @import("std");

const tidy = @cImport({
    @cInclude("tidy.h");
    @cInclude("tidybuffio.h");
});

fn renderNode(tdoc: tidy.TidyDoc, node: tidy.TidyNode, writer: anytype) !void {
    const node_type = tidy.tidyNodeGetType(node);

    if (node_type == tidy.TidyNode_Text) {
        var buf = std.mem.zeroes(tidy.TidyBuffer);
        tidy.tidyBufInit(&buf);
        defer tidy.tidyBufFree(&buf);

        if (tidy.tidyNodeGetValue(tdoc, node, &buf) == tidy.no) {
            return error.TidyError;
        }

        try writer.writeAll(buf.bp[0..buf.size]);
    }

    var child = tidy.tidyGetChild(node);
    while (child != null) : (child = tidy.tidyGetNext(child)) {
        try renderNode(tdoc, child, writer);
    }

    const tag = tidy.tidyNodeGetId(node);

    if (tag == tidy.TidyTag_P) {
        try writer.writeAll("\n\n");
    } else if (tag == tidy.TidyTag_BR) {
        try writer.writeAll("\n");
    }
}

pub fn renderHtml(input: []const u8, writer: anytype) !void {
    const tdoc = tidy.tidyCreate();
    defer tidy.tidyRelease(tdoc);

    if (tidy.tidyOptSetBool(tdoc, tidy.TidyXhtmlOut, tidy.yes) == tidy.no)
        return error.TidyError;
    if (tidy.tidyOptSetBool(tdoc, tidy.TidyBodyOnly, tidy.yes) == tidy.no)
        return error.TidyError;
    if (tidy.tidyOptSetBool(tdoc, tidy.TidyShowWarnings, tidy.no) == tidy.no)
        return error.TidyError;
    if (tidy.tidyOptSetInt(tdoc, tidy.TidyShowErrors, 0) == tidy.no)
        return error.TidyError;
    if (tidy.tidyOptSetBool(tdoc, tidy.TidyQuiet, tidy.yes) == tidy.no)
        return error.TidyError;

    var inbuf = std.mem.zeroes(tidy.TidyBuffer);
    tidy.tidyBufInit(&inbuf);
    defer tidy.tidyBufFree(&inbuf);

    tidy.tidyBufAppend(&inbuf, @intToPtr(?*anyopaque, @ptrToInt(input.ptr)), @intCast(c_uint, input.len));
    if (tidy.tidyParseBuffer(tdoc, &inbuf) < 0)
        return error.HtmlError;

    const root = tidy.tidyGetRoot(tdoc);
    try renderNode(tdoc, root, writer);
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
