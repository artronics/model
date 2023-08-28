const std = @import("std");
const vfs = @import("vfs.zig");

pub const Vfs = vfs.Vfs;
pub const VFile = vfs.VFile;

test "basic add functionality" {
    try std.testing.expect(true);
}
