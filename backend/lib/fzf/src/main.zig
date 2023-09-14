const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const algo = @import("algo.zig");
const term = @import("term.zig");
const testing = std.testing;
const expect = testing.expect;

pub const match = algo.match;
pub const MatchType = algo.MatchType;

pub const MatchFinder = struct {
    const Self = @This();

    allocator: Allocator,
    term: term.Term,
    smart_case: bool = false,
    haystack: []const []const u8,

    pub fn init(allocator: Allocator, texts: []const []const u8) Self {
        return .{
            .allocator = allocator,
            .term = term.Term.init(allocator),
            .haystack = texts,
        };
    }
    pub fn deinit(self: Self) void {
        self.term.deinit();
    }
    pub fn search(self: *Self, term_str: []const u8) !?isize {
        try self.term.parse(term_str);
        return self.reduceScore(null, self.term.expr);
    }
    fn reduceScore(self: Self, acc: ?isize, expr: term.Expr) ?isize {
        return switch (expr) {
            term.Expr.chunk => |chunk| {
                return if (self.matchChunk(chunk)) |s| {
                    return if (acc) |ss| {
                        // FIXME: Should it be addition or max? same for other branches
                        // return ss +| s;
                        return @max(s, ss);
                    } else s;
                } else null;
            },
            term.Expr.and_op => |op| {
                const ls = self.reduceScore(acc, op.l.*);
                return if (ls) |s| {
                    const rs = self.reduceScore(s, op.r.*);
                    return if (rs) |ss| {
                        // return s +| ss;
                        return @max(s, ss);
                    } else null;
                } else null;
            },
            term.Expr.or_op => |op| {
                const ls = self.reduceScore(acc, op.l.*);
                return if (ls) |s| {
                    return s;
                } else {
                    const rs = self.reduceScore(acc, op.r.*);
                    return if (rs) |ss| ss else null;
                };
            },
        };
    }
    fn matchChunk(self: Self, chunk: term.Chunk) ?isize {
        const Cmt = term.Chunk.MatchType;
        const mt = switch (chunk.match_type) {
            Cmt.fuzzy => MatchType.fuzzy,
            Cmt.exact => MatchType.exact,
            Cmt.suffix_exact => MatchType.suffix_exact,
            Cmt.prefix_exact => MatchType.prefix_exact,
            Cmt.inverse_exact => MatchType.inverse_exact,
            Cmt.inverse_prefix_exact => MatchType.inverse_prefix_exact,
            Cmt.inverse_suffix_exact => MatchType.inverse_suffix_exact,
        };

        const case_sen = self.smart_case and caseVaries(chunk.pattern);

        return match(self.haystack[0], chunk.pattern, case_sen, mt);
    }
};

fn caseVaries(text: []const u8) bool {
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

test "Matcher" {
    const a = testing.allocator;
    const texts = [_][]const u8{"foo bar baz"};
    // const texts = [_][]const u8{ "bite continue delightful", "earthwax summary emotion", "sticks notify banish" };
    var matcher = MatchFinder.init(a, &texts);
    defer matcher.deinit();

    const score = try matcher.search("foo | bar baz");
    try expect(score != null);
}
