const std = @import("std");
const Allocator = std.mem.Allocator;

pub const MatchType = enum {
    fuzzy,
    exact,
    prefix_exact,
    suffix_exact,
    inverse_exact,
    inverse_prefix_exact,
    inverse_suffix_exact,
};

pub const Chunk = struct {
    pattern: []const u8 = undefined,
    match_type: MatchType = MatchType.fuzzy,

    fn allocPrint(chunk: Chunk, alloc: Allocator) ![]const u8 {
        const MT = MatchType;
        return switch (chunk.match_type) {
            MT.fuzzy => std.fmt.allocPrint(alloc, "{s}", .{chunk.pattern}),
            MT.exact => std.fmt.allocPrint(alloc, "'{s}", .{chunk.pattern}),
            MT.prefix_exact => std.fmt.allocPrint(alloc, "^{s}", .{chunk.pattern}),
            MT.suffix_exact => std.fmt.allocPrint(alloc, "{s}$", .{chunk.pattern}),
            MT.inverse_exact => std.fmt.allocPrint(alloc, "!{s}", .{chunk.pattern}),
            MT.inverse_prefix_exact => std.fmt.allocPrint(alloc, "!^{s}", .{chunk.pattern}),
            MT.inverse_suffix_exact => std.fmt.allocPrint(alloc, "!{s}$", .{chunk.pattern}),
        };
    }
};
