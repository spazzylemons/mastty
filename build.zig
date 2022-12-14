const deps = @import("deps.zig");
const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("mastty", "src/main.zig");
    exe.linkLibC();
    exe.linkSystemLibrary("ssl");
    exe.linkSystemLibrary("crypto");
    exe.linkSystemLibrary("readline");
    exe.linkSystemLibrary("tidy");
    exe.linkSystemLibrary("ncursesw");
    deps.addAllTo(exe);
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    // readline doesn't vibe with zig build run, idk why
    // const run_cmd = exe.run();
    // run_cmd.step.dependOn(b.getInstallStep());
    // if (b.args) |args| {
    //     run_cmd.addArgs(args);
    // }

    // const run_step = b.step("run", "Run the app");
    // run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
