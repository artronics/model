const std = @import("std");
const fzf = @import("fzf");

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("\nvalue from lib: {s}\n", .{@tagName(fzf.MatchType.exact)});
}

test "simple test" {}
