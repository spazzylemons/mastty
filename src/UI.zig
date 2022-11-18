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
//! along with this program.  If not, see <http://www.gnu.org/licenses/>.

const curses = @import("curses.zig");
const std = @import("std");
const readline = @import("readline.zig");
const util = @import("util.zig");

const UI = @This();

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
pub fn cmdWinRedisplay(self: UI, for_resize: bool) !void {
    const prompt = std.mem.span(readline.c.rl_display_prompt);
    const line = std.mem.span(readline.c.rl_line_buffer);
    const prompt_width = util.stringWidth(prompt);
    const cursor_col = prompt_width + util.stringWidth(line[0..@intCast(usize, readline.c.rl_point)]);

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

fn handleChar(self: *UI, char: c_int) void {
    if (std.math.cast(u8, char)) |ch| {
        self.forwardToReadline(ch);
    }
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

pub fn gotCommand(self: *UI, line: ?[*:0]u8) !void {
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

pub fn setupReadline(self: *UI) void {
    readline.setupUi(self);
}

pub fn initUi(allocator: std.mem.Allocator) !UI {
    try util.initLocale();

    // TODO check result
    const screen = try curses.initScreen();
    errdefer curses.endWin();

    try curses.cBreak();
    try curses.noEcho();
    try curses.noNl();
    try screen.interFlush(false);

    curses.setCursor(.very_visible);

    var ui = try UI.init(allocator);
    errdefer ui.deinit();

    ui.msg.scrollOk(true);

    try ui.sep.background(curses.c.A_STANDOUT);
    ui.sep.refresh();
    try ui.msgWinRedisplay(false);

    return ui;
}

pub fn deinitUi(ui: UI) void {
    curses.endWin();
    ui.deinit();
    readline.c.rl_callback_handler_remove();
}

