pub const c = @cImport({
    @cInclude("curses.h");
});

const std = @import("std");

pub const Window = struct {
    ptr: *c.WINDOW,

    pub fn init(ln: c_int, cl: c_int, y: c_int, x: c_int) !Window {
        const ptr = c.newwin(ln, cl, y, x) orelse return error.CursesError;
        return Window{ .ptr = ptr };
    }

    pub fn deinit(self: Window) void {
        _ = c.delwin(self.ptr);
    }

    pub fn erase(self: Window) void {
        _ = c.werase(self.ptr);
    }

    pub fn noOutRefresh(self: Window) void {
        // assume not a pad
        _ = c.wnoutrefresh(self.ptr);
    }

    pub fn refresh(self: Window) void {
        // assume not a pad
        _ = c.wrefresh(self.ptr);
    }

    pub fn resize(self: Window, ln: c_int, cl: c_int) !void {
        if (c.wresize(self.ptr, ln, cl) == c.ERR) {
            return error.CursesError;
        }
    }

    pub fn scrollOk(self: Window, bf: bool) void {
        _ = c.scrollok(self.ptr, bf);
    }

    pub fn move(self: Window, y: c_int, x: c_int) !void {
        if (c.mvwin(self.ptr, y, x) == c.ERR) {
            return error.CursesError;
        }
    }

    pub fn moveCursor(self: Window, y: c_int, x: c_int) !void {
        if (c.wmove(self.ptr, y, x) == c.ERR) {
            return error.CursesError;
        }
    }

    pub fn getChar(self: Window) c_int {
        return c.wgetch(self.ptr);
    }

    fn addString(self: Window, msg: []const u8) !void {
        if (c.waddnstr(self.ptr, msg.ptr, @intCast(c_int, msg.len)) == c.ERR) {
            return error.CursesError;
        }
    }

    fn write(self: Window, buf: []const u8) error{CursesError}!usize {
        try self.addString(buf);
        return buf.len;
    }

    pub fn writer(self: Window) std.io.Writer(Window, error{CursesError}, write) {
        return .{ .context = self };
    }

    pub fn interFlush(self: Window, value: bool) !void {
        if (c.intrflush(self.ptr, value) == c.ERR) {
            return error.CursesError;
        }
    }

    pub fn background(self: Window, ch: c.chtype) !void {
        if (c.wbkgd(self.ptr, ch) == c.ERR) {
            return error.CursesError;
        }
    }

    pub fn current() Window {
        return Window{ .ptr = c.curscr };
    }

    pub fn clearOk(self: Window, value: bool) !void {
        if (c.clearok(self.ptr, value) == c.ERR) {
            return error.CursesError;
        }
    }
};

pub const Visibility = enum {
    invisible,
    visible,
    very_visible,
};

pub fn setCursor(visibility: Visibility) void {
    _ = c.curs_set(@enumToInt(visibility));
}

pub fn initScreen() !Window {
    const ptr = c.initscr() orelse return error.CursesError;
    return Window{ .ptr = ptr };
}

pub fn endWin() void {
    _ = c.endwin();
}

pub fn doUpdate() !void {
    if (c.doupdate() == c.ERR) {
        return error.CursesError;
    }
}

pub fn cBreak() !void {
    if (c.cbreak() == c.ERR) {
        return error.CursesError;
    }
}

pub fn noEcho() !void {
    if (c.noecho() == c.ERR) {
        return error.CursesError;
    }
}

pub fn noNl() !void {
    if (c.nonl() == c.ERR) {
        return error.CursesError;
    }
}

pub fn lines() c_int {
    return c.LINES;
}

pub fn cols() c_int {
    return c.COLS;
}
