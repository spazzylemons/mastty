//! A minimal wrapper for OpenSSL containing just the methods needed.

const c = @cImport({
    @cInclude("openssl/err.h");
    @cInclude("openssl/ssl.h");
    @cInclude("stdio.h");
});

const std = @import("std");

fn printErrors() void {
    c.ERR_print_errors_fp(c.stderr);
}

pub const Method = struct {
    ptr: *const c.SSL_METHOD,

    pub fn client() Method {
        return .{ .ptr = c.TLS_client_method() orelse unreachable };
    }
};

pub const Error = error{OpenSSLError};

pub const Context = struct {
    ptr: *c.SSL_CTX,

    pub fn init(method: Method) Error!Context {
        const ptr = c.SSL_CTX_new(method.ptr) orelse {
            printErrors();
            return error.OpenSSLError;
        };
        return Context { .ptr = ptr };
    }

    pub fn deinit(self: Context) void {
        c.SSL_CTX_free(self.ptr);
    }
};

pub const SSL = struct {
    ptr: *c.SSL,

    pub fn init(context: Context) Error!SSL {
        const ptr = c.SSL_new(context.ptr) orelse {
            printErrors();
            return error.OpenSSLError;
        };
        return SSL { .ptr = ptr };
    }

    pub fn deinit(self: SSL) void {
        c.SSL_free(self.ptr);
    }

    pub fn setStream(self: SSL, stream: std.net.Stream) Error!void {
        if (c.SSL_set_fd(self.ptr, stream.handle) == 0) {
            printErrors();
            return error.OpenSSLError;
        }
    }

    pub fn setTLSExtHostName(self: SSL, name: [*:0]const u8) Error!void {
        if (c.SSL_set_tlsext_host_name(self.ptr, name) == 0) {
            printErrors();
            return error.OpenSSLError;
        }
    }

    pub fn connect(self: SSL) Error!void {
        if (c.SSL_connect(self.ptr) <= 0) {
            printErrors();
            return error.OpenSSLError;
        }
    }

    fn read(self: SSL, buf: []u8) Error!usize {
        if (buf.len == 0) return 0;
        const len = std.math.min(buf.len, std.math.maxInt(c_int));
        const amt = c.SSL_read(self.ptr, buf.ptr, @intCast(c_int, len));
        if (amt <= 0) {
            printErrors();
            return error.OpenSSLError;
        }
        return @intCast(usize, amt);
    }

    pub const Reader = std.io.Reader(SSL, Error, read);

    pub fn reader(self: SSL) Reader {
        return .{ .context = self };
    }

    fn write(self: SSL, buf: []const u8) Error!usize {
        if (buf.len == 0) return 0;
        const len = std.math.min(buf.len, std.math.maxInt(c_int));
        const amt = c.SSL_write(self.ptr, buf.ptr, @intCast(c_int, len));
        if (amt <= 0) {
            printErrors();
            return error.OpenSSLError;
        }
        return @intCast(usize, amt);
    }

    pub const Writer = std.io.Writer(SSL, Error, write);

    pub fn writer(self: SSL) Writer {
        return .{ .context = self };
    }

    pub fn shutdown(self: SSL) void {
        _ = c.SSL_shutdown(self.ptr);
    }
};
