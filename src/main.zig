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

fn greetUser(rest: *RestClient) !void {
    const acct = try rest.get(entities.Account, "/api/v1/accounts/verify_credentials");
    defer acct.deinit(rest.allocator);
    try std.io.getStdOut().writer().print("hello, {s}!\n", .{acct.username});
}

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

fn printUsage() !void {
    const writer = std.io.getStdErr().writer();
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
        try printUsage();
        try std.io.getStdErr().writer().print("type {s} --help for more information.\n", .{getProgramName()});
        std.os.exit(1);
    };
    defer res.deinit();

    if (res.args.help) {
        try printUsage();
        try std.io.getStdErr().writer().writeAll("options:\n");
        try std.io.getStdErr().writer().writeAll(paramsString);
        std.os.exit(0);
    }
}

pub fn main() !void {
    try handleArguments();

    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = try Config.open(allocator);
    defer config.deinit(allocator);

    // get rest client
    var rest = try config.createRestClient(allocator);
    defer rest.deinit();

    try greetUser(&rest);

    const status = try readline.line(allocator, "status to post? ");
    defer allocator.free(status);
    if (status.len != 0) {
        const Foo = struct {};
        _ = try rest.post(Foo, "/api/v1/statuses", .{
            .status = status,
            .media_ids = null,
            .poll = null,
        });
    }
}
