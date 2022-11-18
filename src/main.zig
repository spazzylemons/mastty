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

const clap = @import("clap");
const Config = @import("Config.zig");
const curses = @import("curses.zig");
const entities = @import("entities.zig");
const readline = @import("readline.zig");
const RestClient = @import("RestClient.zig");
const std = @import("std");
const Timeline = @import("Timeline.zig");

const paramsString =
    \\-h, --help  Display help and exit.
    \\
;

const params = clap.parseParamsComptime(paramsString);

fn getProgramName() []const u8 {
    if (std.os.argv.len != 0) {
        return std.mem.span(std.os.argv[0]);
    } else {
        return "mastty";
    }
}

fn printUsage(file: std.fs.File) !void {
    const writer = file.writer();
    try writer.print("usage: {s} ", .{getProgramName()});
    try clap.usage(writer, clap.Help, &params);
    try writer.writeAll("\n");
}

fn handleArguments() !void {
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch |err| {
        try diag.report(std.io.getStdErr().writer(), err);
        try printUsage(std.io.getStdErr());
        try std.io.getStdErr().writer().print("type {s} --help for more information.\n", .{getProgramName()});
        std.os.exit(1);
    };
    defer res.deinit();

    if (res.args.help) {
        try printUsage(std.io.getStdOut());
        try std.io.getStdOut().writer().writeAll("options:\n");
        try std.io.getStdOut().writer().writeAll(paramsString);
        std.os.exit(0);
    }
}

fn getHomeTimeline(rest: *RestClient) !Timeline {
    // if command is home, then for testing, print 10 home timeline statuses
    const statuses = try rest.get([]entities.Status, "/api/v1/timelines/home?limit=10");
    errdefer std.json.parseFree([]entities.Status, statuses, .{ .allocator = rest.allocator });
    return try Timeline.init(rest.allocator, statuses);
}

const UI = @import("UI.zig");

pub fn main() !void {
    // we must be in interactive mode
    if (!std.io.getStdOut().isTty()) {
        try std.io.getStdErr().writer().writeAll("mastty must be run in interactive mode.\n");
        std.os.exit(1);
    }

    try handleArguments();

    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = try Config.open(allocator);
    defer config.deinit(allocator);

    // get rest client
    var rest = try config.createRestClient(allocator);
    defer rest.deinit();

    var my_ui = try UI.initUi(allocator);
    defer my_ui.deinitUi();
    my_ui.setupReadline();

    my_ui.msg.erase();

    try my_ui.msg.moveCursor(0, 0);
    my_ui.msg.refresh();

    const acct = try rest.get(entities.Account, "/api/v1/accounts/verify_credentials");
    defer acct.deinit(rest.allocator);

    try my_ui.sep.moveCursor(0, 0);
    try my_ui.sep.writer().print("hello, {s}!", .{ acct.username });
    my_ui.sep.refresh();

    var timeline: ?Timeline = null;
    defer if (timeline) |tl| tl.deinit();
    var timeline_offset: c_int = 0;

    while (try my_ui.getLine()) |command| {
        defer allocator.free(command);

        if (std.mem.eql(u8, command, "exit")) {
            // if command is exit, then quit
            break;
        } else if (std.mem.eql(u8, command, "home")) {
            if (getHomeTimeline(&rest)) |tl| {
                if (timeline) |old_tl| old_tl.deinit();
                timeline = tl;
                timeline_offset = 0;
            } else |err| {
                try my_ui.sep.moveCursor(0, 0);
                try my_ui.sep.writer().print("error: {s}", .{ @errorName(err) });
                my_ui.sep.refresh();
            }
        } else if (std.mem.eql(u8, command, "up")) {
            // TODO shortcut keys
            timeline_offset -= 1;
        } else if (std.mem.eql(u8, command, "down")) {
            // TODO shortcut keys
            timeline_offset += 1;
        } else {
            // TODO help system
        }

        // TODO rerender only when needed?
        // and also rerender on resize
        if (timeline) |tl| {
            try tl.render(my_ui.msg, timeline_offset, my_ui.msg.getMaxY());
        }
    }
}
