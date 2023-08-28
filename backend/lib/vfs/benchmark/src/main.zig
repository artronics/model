const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const vfs = @import("vfs");
const time = std.time;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const a = gpa.allocator();
    try run(a, "benchmark/data/zig");

    std.debug.assert(!gpa.detectLeaks());
}

fn run(allocator: Allocator, path: []const u8) !void {
    const f = try std.fs.cwd().realpathAlloc(allocator, path);
    defer allocator.free(f);
    var string = ArrayList(u8).init(allocator);
    defer string.deinit();

    var timer = try time.Timer.start();
    const fs = try vfs.Vfs.init(allocator, f);
    defer fs.deinit();
    try fs.root.print(&string);
    const elapsed = timer.lap();

    std.log.warn("result: {s}", .{string.items});
    std.log.warn("TIME: {d}ms", .{elapsed / 1000_000});
}
