//! mastty - CLI client for mastodon
//! Copyright (C) 2022 spazzylemons
//!
//! This program is free software: you can redistribute it and/or modify
//! it under the terms of the GNU General Public License as published by
//! the Free Software Foundation, either version 3 of the License, or
//! (at your option) any later version.
//!
//! This program is distributed in the hope that it will be useful,
//! but WITHOUT ANY WARRANTY; without even the implied warranty of
//! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//! GNU General Public License for more details.
//!
//! You should have received a copy of the GNU General Public License

const curses = @import("curses.zig");
const std = @import("std");
const readline = @import("readline.zig");

const UI = struct {
    msg: curses.Window,
    sep: curses.Window,
    cmd: curses.Window,
    input: ?u8 = null,
    should_exit: bool = false,
    line: ?[]const u8 = null,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) !UI {
        if (curses.lines() >= 3) {
            const message_window = try curses.Window.init(curses.lines() - 2, curses.cols(), 0, 0);
            errdefer message_window.deinit();

            const separator_window = try curses.Window.init(1, curses.cols(), curses.lines() - 2, 0);
            errdefer separator_window.deinit();

            const command_window = try curses.Window.init(1, curses.cols(), curses.lines() - 1, 0);
            errdefer command_window.deinit();

            return UI{
                .msg = message_window,
                .sep = separator_window,
                .cmd = command_window,
                .allocator = allocator,
            };
        } else {
            const message_window = try curses.Window.init(1, curses.cols(), 0, 0);
            errdefer message_window.deinit();

            const separator_window = try curses.Window.init(1, curses.cols(), 0, 0);
            errdefer separator_window.deinit();

            const command_window = try curses.Window.init(1, curses.cols(), 0, 0);
            errdefer command_window.deinit();

            return UI{
                .msg = message_window,
                .sep = separator_window,
                .cmd = command_window,
                .allocator = allocator,
            };
        }
    }

    fn deinit(self: UI) void {
        self.msg.deinit();
        self.sep.deinit();
        self.cmd.deinit();
    }

    fn forwardToReadline(self: *UI, ch: u8) void {
        self.input = ch;
        readline.c.rl_callback_read_char();
    }

    fn msgWinRedisplay(self: UI, for_resize: bool) !void {
        if (for_resize) {
            self.msg.noOutRefresh();
        } else {
            self.msg.refresh();
        }
    }

    // TODO scrolling
    fn cmdWinRedisplay(self: UI, for_resize: bool) !void {
        const prompt = std.mem.span(readline.c.rl_display_prompt);
        const line = std.mem.span(readline.c.rl_line_buffer);
        const prompt_width = stringWidth(prompt);
        const cursor_col = prompt_width + stringWidth(line[0..@intCast(usize, readline.c.rl_point)]);

        self.cmd.erase();
        try self.cmd.moveCursor(0, 0);
        try self.cmd.writer().print("{s}{s}", .{prompt, line});
        if (cursor_col >= curses.cols()) {
            curses.setCursor(.invisible);
        } else {
            try self.cmd.moveCursor(0, @intCast(c_int, cursor_col));
            curses.setCursor(.very_visible);
        }

        if (for_resize) {
            self.cmd.noOutRefresh();
        } else {
            self.cmd.refresh();
        }
    }

    fn resize(self: UI) !void {
        if (curses.lines() >= 3) {
            try self.msg.resize(curses.lines() - 2, curses.cols());
            try self.sep.resize(1, curses.cols());
            try self.cmd.resize(1, curses.cols());

            try self.sep.move(curses.lines() - 2, 0);
            try self.cmd.move(curses.lines() - 1, 0);
        }

        try self.msgWinRedisplay(true);
        self.sep.noOutRefresh();
        try self.cmdWinRedisplay(true);
        try curses.doUpdate();
    }

    pub fn getLine(self: *UI) !?[]const u8 {
        while (true) {
            if (self.should_exit) {
                return null;
            }
            if (self.line) |l| {
                self.line = null;
                return l;
            }
            switch (self.cmd.getChar()) {
                curses.c.KEY_RESIZE => try self.resize(),
                0x0c => {
                    try curses.Window.current().clearOk(true);
                    try self.resize();
                },
                else => |ch| if (std.math.cast(u8, ch)) |char| self.forwardToReadline(char),
            }
        }
    }

    fn myGotCommand(self: *UI, line: ?[*:0]u8) !void {
        if (line) |l| {
            defer readline.c.free(l);

            const copy = try self.allocator.dupe(u8, std.mem.span(l));
            if (copy.len > 0) {
                readline.addHistory(l);
            }
            if (self.line) |l1| {
                self.allocator.free(l1);
            }
            self.line = copy;

            try self.msgWinRedisplay(false);
        } else {
            self.should_exit = true;
        }
    }
};

pub var ui: UI = undefined;

pub const locale = @cImport({
    @cInclude("locale.h");
    @cInclude("wchar.h");
});

fn stringWidth(s: []const u8) usize {
    // string width fallback will be length in bytes
    var it = (std.unicode.Utf8View.init(s) catch return s.len).iterator();
    var width: usize = 0;
    while (it.nextCodepoint()) |wc| {
        width += std.math.cast(usize, locale.wcwidth(wc)) orelse 1;
    }
    return width;
}

fn gotCommand(line: ?[*:0]u8) callconv(.C) void {
    ui.myGotCommand(line) catch {};
}

fn readlineMatches(matches: [*c][*c]u8, len: c_int, max: c_int) callconv(.C) void {
    _ = matches;
    _ = len;
    _ = max;
}

fn getcFunction(unused_file: ?*readline.c.FILE) callconv(.C) c_int {
    _ = unused_file;
    const result = ui.input.?;
    ui.input = null;
    return result;
}

fn inputAvailableHook() callconv(.C) c_int {
    return @boolToInt(ui.input != null);
}

fn redisplayFunction() callconv(.C) void {
    ui.cmdWinRedisplay(false) catch {};
}

pub fn initUi(allocator: std.mem.Allocator) !void {
    if (locale.setlocale(locale.LC_ALL, "") == null) {
        return error.NoLocale;
    }

    // TODO check result
    const screen = try curses.initScreen();
    errdefer curses.endWin();

    try curses.cBreak();
    try curses.noEcho();
    try curses.noNl();
    try screen.interFlush(false);

    curses.setCursor(.very_visible);

    ui = try UI.init(allocator);
    errdefer ui.deinit();

    ui.msg.scrollOk(true);

    try ui.sep.background(curses.c.A_STANDOUT);
    ui.sep.refresh();
    try ui.msgWinRedisplay(false);

    // let ncurses handle signals
    readline.c.rl_catch_signals = 0;
    // let ncurses handle resize
    readline.c.rl_catch_sigwinch = 0;
    // let ncurses configure terminal
    readline.c.rl_deprep_term_function = null;
    readline.c.rl_prep_term_function = null;
    // don't mess with LINES and COLUMNS vars
    readline.c.rl_change_environment = 0;
    // provide our own input
    readline.c.rl_getc_function = getcFunction;
    readline.c.rl_input_available_hook = inputAvailableHook;
    // render things our own way
    readline.c.rl_redisplay_function = redisplayFunction;
    // don't display tab completion options
    readline.c.rl_completion_display_matches_hook = readlineMatches;
    // c.rl_completion_entry_function = readlineCompletion;
    readline.c.rl_callback_handler_install(":", gotCommand);
}

pub fn deinitUi() void {
    curses.endWin();
    ui.deinit();
    readline.c.rl_callback_handler_remove();
}
