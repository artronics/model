const std = @import("std");
const testing = std.testing;

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

export fn backendHandleEvent(str: [*:0]const u8, len: usize) void {
    _ = len;
    _ = str;
    std.log.warn("received  from rust", .{});
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}
