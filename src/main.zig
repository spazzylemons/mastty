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

const Config = @import("Config.zig");
const entities = @import("entities.zig");
const readline = @import("readline.zig");
const RestClient = @import("RestClient.zig");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = try Config.open(allocator);
    defer config.deinit(allocator);

    // get rest client
    var rest = try config.createRestClient(allocator);
    defer rest.deinit();

    // print a greeting
    {
        const acct = try rest.get(entities.Account, "/api/v1/accounts/verify_credentials");
        defer acct.deinit(allocator);
        try std.io.getStdOut().writer().print("hello, {s}!\n", .{acct.username});
    }

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

    // var foo = try rest.get("/api/v1/timelines/public?limit=2");
    // defer foo.deinit();

    // std.log.info("{}", .{foo.root});
}
