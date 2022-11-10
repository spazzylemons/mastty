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

const entities = @import("entities.zig");
const readline = @import("readline.zig");
const RestClient = @import("RestClient.zig");
const std = @import("std");

const Config = @This();

pub const ClientInfo = struct {
    id: []const u8,
    secret: []const u8,
};

instance: ?[]const u8 = null,

client: ?ClientInfo = null,

access_token: ?[]const u8 = null,

fn mkdirs(path: []const u8) !void {
    var it = std.mem.tokenize(u8, path, "/");
    var dir = try std.fs.cwd().openDir(if (std.mem.startsWith(u8, path, "/")) "/" else ".", .{});
    defer dir.close();

    while (it.next()) |part| {
        dir.makeDir(part) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => |e| return e,
        };
        const new_dir = try dir.openDir(part, .{});
        dir.close();
        dir = new_dir;
    }
}

fn openConfigDir(temp_allocator: std.mem.Allocator) !std.fs.Dir {
    // TODO multiplatform config dir
    const config_path_name = if (std.os.getenvZ("XDG_CONFIG_HOME")) |config|
        try std.fmt.allocPrint(temp_allocator, "{s}/mastty", .{config})
    else try std.fmt.allocPrint(temp_allocator, "{s}/.config/mastty", .{std.os.getenvZ("HOME").?});
    defer temp_allocator.free(config_path_name);
    try mkdirs(config_path_name);
    return try std.fs.cwd().openDir(config_path_name, .{});
}

fn ensureConfigExists(dir: std.fs.Dir) !void {
    // use exclusive create
    const file = dir.createFile("config.json", .{ .exclusive = true }) catch |err| switch (err) {
        // file exists, no need to create
        error.PathAlreadyExists => return,
        // other error
        else => |e| return e,
    };
    defer file.close();
    // write a default config
    try std.json.stringify(Config{}, .{}, file.writer());
}

pub fn open(allocator: std.mem.Allocator) !Config {
    var dir = try openConfigDir(allocator);
    defer dir.close();

    try ensureConfigExists(dir);

    const file = try dir.openFile("config.json", .{});
    defer file.close();

    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);

    var stream = std.json.TokenStream.init(file_contents);
    return try std.json.parse(Config, &stream, .{ .allocator = allocator });
}

pub fn deinit(self: Config, allocator: std.mem.Allocator) void {
    std.json.parseFree(Config, self, .{ .allocator = allocator });
}

pub fn write(self: Config, temp_allocator: std.mem.Allocator) !void {
    var dir = try openConfigDir(temp_allocator);
    defer dir.close();

    try ensureConfigExists(dir);

    const file = try dir.createFile("config.json", .{});
    defer file.close();

    try std.json.stringify(self, .{}, file.writer());
}

pub fn getInstance(self: *Config, allocator: std.mem.Allocator) ![]const u8 {
    if (self.instance == null) {
        const line = try readline.line(allocator, "what instance? ");
        if (line.len == 0) return error.EmptyLine;
        self.instance = line;
        try self.write(allocator);
    }
    return self.instance.?;
}

pub fn getClientInfo(self: *Config, allocator: std.mem.Allocator, rest: *RestClient) !ClientInfo {
    if (self.client == null) {
        var app = try rest.post(entities.Application, "/api/v1/apps", .{
            .client_name = "mastty CLI",
            .redirect_uris = "urn:ietf:wg:oauth:2.0:oob",
            .scopes = "read write follow push",
            .website = "https://github.com/spazzylemons/mastty",
        });
        defer app.deinit(allocator);

        // success, insert client id and client secret
        self.client = .{
            .id = app.client_id,
            .secret = app.client_secret,
        };
        app.client_id = &.{};
        app.client_secret = &.{};
        try self.write(allocator);
    }
    return self.client.?;
}

pub fn createRestClient(self: *Config, allocator: std.mem.Allocator) !RestClient {
    const instance = try self.getInstance(allocator);

    var rest = try RestClient.init(allocator, instance);
    errdefer rest.deinit();

    const client = try self.getClientInfo(allocator, &rest);

    if (self.access_token == null) {
        // TODO portability
        const auth_url = try std.fmt.allocPrintZ(allocator, "https://{s}/oauth/authorize?client_id={s}&scope=read+write+follow+push&redirect_uri=urn:ietf:wg:oauth:2.0:oob&response_type=code", .{instance, client.id});
        defer allocator.free(auth_url);
        const pid = try std.os.fork();
        if (pid == 0) {
            const argv = [_:null]?[*:0]const u8 { "xdg-open", auth_url, null };
            const err = std.os.execvpeZ("xdg-open", &argv, std.c.environ);
            std.io.getStdErr().writer().print("failed to run xdg-open: {s}\n", .{@errorName(err)}) catch {};
            std.os.exit(1);
        }
        _ = std.os.waitpid(pid, 0);
        const code = try readline.line(allocator, "enter the authorization code from the browser: ");
        defer allocator.free(code);
        // empty code, quit
        if (code.len == 0) return error.EmptyLine;
        // get a token
        var token = try rest.post(entities.Token, "/oauth/token", .{
            .client_id = client.id,
            .client_secret = client.secret,
            .redirect_uri = "urn:ietf:wg:oauth:2.0:oob",
            .grant_type = "authorization_code",
            .code = code,
            .scope = "read write follow push"
        });
        defer token.deinit(allocator);

        self.access_token = token.access_token;
        token.access_token = &.{};
        try self.write(allocator);
    }

    rest.authorization = self.access_token.?;

    return rest;
}
