const std = @import("std");
const benchmark = @import("benchmark/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "vfs",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(lib);
    // benchmark
    var bench_exe = benchmark.package(b, optimize, target);
    bench_exe.linkLibrary(lib);
    b.installArtifact(bench_exe);

    const run_benchmark = b.addRunArtifact(bench_exe);
    run_benchmark.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_benchmark.addArgs(args);
    }
    const run_bench_step = b.step("benchmark", "Run the example app");
    run_bench_step.dependOn(&run_benchmark.step);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
