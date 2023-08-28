const std = @import("std");
const ArrayList = std.ArrayList;
const vfs = @import("vfs");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const a = arena.allocator();

    const f = try std.fs.cwd().realpathAlloc(a, "benchmark");
    const fs = try vfs.Vfs.init(a, f);

    var string = ArrayList(u8).init(a);
    try fs.root.print(&string);
    std.log.warn("result: {s}", .{string.items});
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
