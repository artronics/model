const std = @import("std");

const testing = std.testing;
const eq = std.testing.expectEqual;
test "vfs" {
    try eq(true, true);
}
