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
const entities = @import("entities.zig");
const readline = @import("readline.zig");
const RestClient = @import("RestClient.zig");
const std = @import("std");

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

pub fn main() !void {
    try handleArguments();

    try std.io.getStdOut().writer().writeAll(
        \\mastty - Copyright (C) 2022 spazzylemons
        \\This program comes with ABSOLUTELY NO WARRANTY; see the
        \\GNU General Public License for more details.
        \\
    );

    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = try Config.open(allocator);
    defer config.deinit(allocator);

    // get rest client
    var rest = try config.createRestClient(allocator);
    defer rest.deinit();

    const acct = try rest.get(entities.Account, "/api/v1/accounts/verify_credentials");
    defer acct.deinit(rest.allocator);

    try std.io.getStdOut().writer().print("hello, {s}!\n", .{acct.username});

    // bash ps1-style prompt - username@instance
    const prompt = try std.fmt.allocPrintZ(allocator, "{s}@{s}> ", .{acct.username, config.instance.?});
    defer allocator.free(prompt);

    while (true) {
        const command = readline.line(allocator, prompt) catch |err| switch (err) {
            // clean exit on EOF
            error.EOF => break,
            else => |e| return e,
        };
        defer allocator.free(command);

        if (std.mem.eql(u8, command, "exit")) {
            // if command is exit, then quit
            break;
        } else if (std.mem.eql(u8, command, "home")) {
            // if command is home, then for testing, print three home timeline statuses
            const statuses = try rest.get([]entities.Status, "/api/v1/timelines/home?limit=3");
            defer std.json.parseFree([]entities.Status, statuses, .{ .allocator = allocator });

            for (statuses) |status| {
                try std.io.getStdOut().writer().print("{s} says {s}\n", .{
                    status.account.url,
                    status.content,
                });
            }
        } else {
            // TODO help system
        }
    }
}
