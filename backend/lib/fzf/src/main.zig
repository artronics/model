const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const algo = @import("algo.zig");
const term = @import("term.zig");
const chk = @import("chunk.zig");
const Chunk = chk.Chunk;
const testing = std.testing;
const expect = testing.expect;

pub const match = algo.match;
pub const MatchType = chk.MatchType;

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
        // short circuit both "and" and "or" by evaluating left branch first
        return switch (expr) {
            term.Expr.chunk => |chunk| {
                return if (self.matchChunk(chunk)) |chunk_s| {
                    return if (acc) |acc_s| {
                        // FIXME: Should it be addition or max? same for other branches
                        // return ss +| s;
                        return @max(chunk_s, acc_s);
                    } else chunk_s;
                } else null;
            },
            term.Expr.and_op => |op| {
                const _ls = self.reduceScore(acc, op.l.*);
                return if (_ls) |ls| {
                    const _rs = self.reduceScore(ls, op.r.*);
                    return if (_rs) |rs| {
                        // return s +| ss;
                        return @max(ls, rs);
                    } else null;
                } else null;
            },
            term.Expr.or_op => |op| {
                const _ls = self.reduceScore(acc, op.l.*);
                return if (_ls) |ls| {
                    return ls;
                } else {
                    const _rs = self.reduceScore(acc, op.r.*);
                    return if (_rs) |rs| rs else null;
                };
            },
        };
    }
    fn matchChunk(self: Self, chunk: Chunk) ?isize {
        const case_sen = self.smart_case and chk.caseVaries(chunk.pattern);

        return match(self.haystack[0], chunk.pattern, case_sen, chunk.match_type);
    }
};

test "Matcher" {
    const a = testing.allocator;
    const texts = [_][]const u8{"foo bar baz"};
    // const texts = [_][]const u8{ "bite continue delightful", "earthwax summary emotion", "sticks notify banish" };
    var matcher = MatchFinder.init(a, &texts);
    defer matcher.deinit();

    const score = try matcher.search("foo | bar baz");
    try expect(score != null);
}
