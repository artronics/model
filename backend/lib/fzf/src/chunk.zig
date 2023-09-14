const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;

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

pub fn caseVaries(text: []const u8) bool {
    if (text.len < 2) return false;

    var case = std.ascii.isUpper(text[0]);
    var i: usize = 1;
    while (i < text.len) : (i += 1) {
        case = case != std.ascii.isUpper(text[i]);
        if (case) {
            return true;
        }
    }

    return false;
}

test "case varies" {
    try expect(!caseVaries(""));
    try expect(!caseVaries("f"));
    try expect(!caseVaries("F"));
    try expect(!caseVaries("FF"));
    try expect(!caseVaries("ff"));

    try expect(caseVaries("Fo"));
    try expect(caseVaries("fF"));
    try expect(caseVaries("fOo"));
    try expect(caseVaries("FoO"));
}
