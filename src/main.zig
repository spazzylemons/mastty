const entities = @import("entities.zig");
const readline = @import("readline.zig");
const RestClient = @import("RestClient.zig");
const std = @import("std");

const Config = struct {
    access_token: ?[]const u8 = null,
    instance: ?[]const u8 = null,
    client_id: ?[]const u8 = null,
    client_secret: ?[]const u8 = null,

    fn deinit(self: Config, allocator: std.mem.Allocator) void {
        std.json.parseFree(Config, self, .{ .allocator = allocator });
    }

    fn write(self: Config, temp_allocator: std.mem.Allocator) !void {
        var dir = try openConfigDir(temp_allocator);
        defer dir.close();

        try ensureConfigExists(dir);

        const file = try dir.createFile("config.json", .{});
        defer file.close();

        try std.json.stringify(self, .{}, file.writer());
    }
};

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

fn readConfigFile(allocator: std.mem.Allocator) !Config {
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = try readConfigFile(allocator);
    defer config.deinit(allocator);

    if (config.instance == null) {
        config.instance = try readline.line(allocator, "what instance? ");
        if (config.instance.?.len == 0) {
            // no instance given, quit
            return;
        }
        try config.write(allocator);
    }

    var rest = try RestClient.init(allocator, config.instance.?);
    defer rest.deinit();

    // TODO use verify_credentials to refresh credentials if needed
    // const Foo = struct {};
    // _ = try rest.get(Foo, "/api/v1/apps/verify_credentials");

    // if we don't have a client ID or client secret, get one
    if (config.client_id == null or config.client_secret == null) {
        var app = try rest.post(entities.Application, "/api/v1/apps", .{
            .client_name = "mastty CLI",
            .redirect_uris = "urn:ietf:wg:oauth:2.0:oob",
            .scopes = "read write follow push",
            .website = "https://github.com/spazzylemons/mastty",
        });
        defer app.deinit(allocator);

        // success, insert client id and client secret
        if (config.client_id) |s| allocator.free(s);
        if (config.client_secret) |s| allocator.free(s);
        config.client_id = app.client_id;
        config.client_secret = app.client_secret;
        app.client_id = &.{};
        app.client_secret = &.{};
        try config.write(allocator);
    }

    // if we don't have an access token, get one
    if (config.access_token == null) {
        // TODO portability
        const auth_url = try std.fmt.allocPrintZ(allocator, "https://{s}/oauth/authorize?client_id={s}&scope=read+write+follow+push&redirect_uri=urn:ietf:wg:oauth:2.0:oob&response_type=code", .{config.instance.?, config.client_id.?});
        defer allocator.free(auth_url);
        const pid = try std.os.fork();
        if (pid == 0) {
            const argv = [_:null]?[*:0]const u8 { "xdg-open", auth_url, null };
            const err = std.os.execvpeZ("xdg-open", &argv, std.c.environ);
            std.io.getStdErr().writer().print("failed to run xdg-open: {s}\n", .{@errorName(err)}) catch {};
            return;
        }
        _ = std.os.waitpid(pid, 0);
        const code = try readline.line(allocator, "enter the authorization code from the browser: ");
        defer allocator.free(code);
        // empty code, quit
        if (code.len == 0) {
            return;
        }
        // get a token
        var token = try rest.post(entities.Token, "/oauth/token", .{
            .client_id = config.client_id.?,
            .client_secret = config.client_secret.?,
            .redirect_uri = "urn:ietf:wg:oauth:2.0:oob",
            .grant_type = "authorization_code",
            .code = code,
            .scope = "read write follow push"
        });
        defer token.deinit(allocator);

        config.access_token = token.access_token;
        token.access_token = &.{};
        try config.write(allocator);
    }

    rest.authorization = config.access_token.?;

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
