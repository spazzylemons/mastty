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

pub const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("readline/history.h");
    @cInclude("readline/readline.h");
});

const std = @import("std");
const UI = @import("UI.zig");

pub fn line(allocator: std.mem.Allocator, prompt: ?[*:0]const u8) ![]const u8 {
    if (c.readline(prompt)) |l| {
        defer c.free(l);
        return try allocator.dupe(u8, std.mem.span(l));
    }
    return error.EOF;
}

pub fn addHistory(l: [*:0]const u8) void {
    c.add_history(l);
}

var global_ui: *UI = undefined;

fn getcFunction(unused_file: ?*c.FILE) callconv(.C) c_int {
    _ = unused_file;
    const result = global_ui.input.?;
    global_ui.input = null;
    return result;
}

fn inputAvailableHook() callconv(.C) c_int {
    return @boolToInt(global_ui.input != null);
}

fn redisplayFunction() callconv(.C) void {
    global_ui.cmdWinRedisplay(false) catch {};
}

fn gotCommand(l: ?[*:0]u8) callconv(.C) void {
    global_ui.gotCommand(l) catch {};
}

fn readlineMatches(matches: [*c][*c]u8, len: c_int, max: c_int) callconv(.C) void {
    _ = matches;
    _ = len;
    _ = max;
}

pub fn setupUi(new_ui: *UI) void {
    global_ui = new_ui;
    // let ncurses handle signals
    c.rl_catch_signals = 0;
    // let ncurses handle resize
    c.rl_catch_sigwinch = 0;
    // let ncurses configure terminal
    c.rl_deprep_term_function = null;
    c.rl_prep_term_function = null;
    // don't mess with LINES and COLUMNS vars
    c.rl_change_environment = 0;
    // provide our own input
    c.rl_getc_function = getcFunction;
    c.rl_input_available_hook = inputAvailableHook;
    // render things our own way
    c.rl_redisplay_function = redisplayFunction;
    // don't display tab completion options
    c.rl_completion_display_matches_hook = readlineMatches;
    // c.rl_completion_entry_function = readlineCompletion;
    c.rl_callback_handler_install(":", gotCommand);
    // re-iniitialize readline
    _ = c.rl_initialize();
}
