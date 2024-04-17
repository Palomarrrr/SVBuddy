const std = @import("std");
const capy = @import("capy");

// Note to self
// | to build for x86 windows
// | `zig build --host-target x86_64-windows`

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "svbuddy",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    //exe.linkSystemLibrary("/bedrock/strata/arch/usr/lib/libgtk-4.so");
    exe.linkSystemLibrary("../../../../../bedrock/strata/arch/usr/lib/libgtk-4.so");
    b.installArtifact(exe);

    const run_cmd = try capy.install(exe, .{ .args = b.args });
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(run_cmd);

    // Building for WebAssembly
    // WebAssembly doesn't have a concept of executables, so the way it works is that we make a shared library and capy exports a '_start' function automatically
    @setEvalBranchQuota(5000);
    const wasm = b.addExecutable(.{
        .name = "svbuddy",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = b.resolveTargetQuery(
            comptime std.Target.Query.parse(.{ .arch_os_abi = "wasm32-freestanding" }) catch unreachable,
        ),
        .optimize = optimize,
    });
    const serve = try capy.install(wasm, .{});
    const serve_step = b.step("serve", "Start a local web server to run this application");
    serve_step.dependOn(serve);

    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
