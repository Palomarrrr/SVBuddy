const std = @import("std");
const build_capy = @import("capy");

// Note to self
// | to build for x86 windows
// | `zig build --Dtarget"x86_64-windows"`

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    // Setting up capy
    const capy_dep = b.dependency("capy", .{
        .target = target,
        .optimize = optimize,
        .app_name = @as([]const u8, "SVBuddy"),
    });
    const capy = capy_dep.module("capy");

    const exe = b.addExecutable(.{
        .name = "SVBuddy",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("capy", capy);
    b.installArtifact(exe);

    const run_cmd = try build_capy.runStep(exe, .{ .args = b.args });
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(run_cmd);

    // Building for WebAssembly
    // WebAssembly doesn't have a concept of executables, so the way it works is that we make a shared library and capy exports a '_start' function automatically
    //@setEvalBranchQuota(5000);
    //const wasm = b.addExecutable(.{
    //    .name = "SVBuddy",
    //    .root_source_file = .{ .cwd_relative = "src/main.zig" },
    //    .target = b.resolveTargetQuery(
    //        comptime std.Target.Query.parse(.{ .arch_os_abi = "wasm32-freestanding" }) catch unreachable,
    //    ),
    //    .optimize = optimize,
    //});
    //const serve = try capy.install(wasm, .{});
    //const serve_step = b.step("serve", "Start a local web server to run this application");
    //serve_step.dependOn(serve);

    const exe_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
