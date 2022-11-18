const locale = @cImport({
    @cInclude("locale.h");
    @cInclude("wchar.h");
});

const std = @import("std");

pub fn stringWidth(s: []const u8) usize {
    // string width fallback will be length in bytes
    var it = (std.unicode.Utf8View.init(s) catch return s.len).iterator();
    var width: usize = 0;
    while (it.nextCodepoint()) |wc| {
        width += std.math.cast(usize, locale.wcwidth(wc)) orelse 1;
    }
    return width;
}

pub fn stringMaxWidth(s: []const u8, max: usize) []const u8 {
    // string width fallback will be length in bytes
    var it = (std.unicode.Utf8View.init(s) catch return s[0..std.math.min(s.len, max)]).iterator();
    var width: usize = 0;
    var i: usize = 0;
    while (it.nextCodepoint()) |wc| {
        width += std.math.cast(usize, locale.wcwidth(wc)) orelse 1;
        if (width > max) break;
        i = it.i;
    }
    return s[0..i];
}

pub fn initLocale() !void {
    if (locale.setlocale(locale.LC_ALL, "") == null) {
        return error.NoLocale;
    }
}
