const std = @import("std");

pub const pkg = std.build.Pkg{
    .name = "fzf",
    .source = .{ .path = thisDir() ++ "/src/fzf.zig" },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = b.addOptions();
    options.addOption(usize, "max_pattern_len", 32);

    const lib = b.addStaticLibrary(.{
        .name = "fzf",
        .root_source_file = .{ .path = "src/fzf.zig" },
        .target = target,
        .optimize = optimize,
    });

    const m = options.createModule();
    lib.addModule("fzf_options", m);

    b.installArtifact(lib);
    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/fzf.zig" },
        .target = target,
        .optimize = optimize,
    });
    main_tests.addModule("fzf_options", m);

    const run_main_tests = b.addRunArtifact(main_tests);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build test`
    // This will evaluate the `test` step rather than the default, which is "install".
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}

pub fn buildTests(
    b: *std.build.Builder,
    build_mode: std.builtin.Mode,
    target: std.zig.CrossTarget,
) *std.build.LibExeObjStep {
    const tests = b.addTest(pkg.source.path);
    tests.setBuildMode(build_mode);
    tests.setTarget(target);
    return tests;
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
