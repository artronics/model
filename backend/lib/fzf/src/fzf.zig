const std = @import("std");
const p = @import("pattern.zig");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const expect = testing.expect;

const max_pattern_len = @import("pattern.zig").max_pattern_len;

const path_separator = [_]u8{ '.', '/', '\\' };
const boundary_set = [_]u8{ '_', ' ', '-' } ++ path_separator;

const Score = struct {
    _copy: isize = 0,
    _delete: isize = 0,
    _boundary: isize = 0,
    _kill: isize = 0,
    _straight_acc: isize = 0,

    const qc: isize = 1;
    const qd: isize = -1;
    const qb: isize = -1;
    const qk: isize = -1;
    inline fn qs(x: u5) isize {
        // TODO: evaluate the below with a comparison test
        // the score of 1 will be +2 which, combined by copy will contribute +3 in total. How this will impact short strings scoring?
        // It feels like the score of 0 and 1 should be all 0?

        // return if (x == 0 or x == 1) 0 else (@as(isize, 1) << (x + 1)) - 1;
        return (@as(isize, 1) << (x + 1)) - 2;
    }

    inline fn copy(self: *Score) void {
        self._copy += 1;
    }
    inline fn delete(self: *Score, x: isize) void {
        self._delete += x;
    }
    inline fn boundary(self: *Score) void {
        self._boundary += 1;
    }
    inline fn kill(self: *Score, x: isize) void {
        self._kill += x;
    }
    inline fn straight(self: *Score, x: u5) void {
        self._straight_acc += qs(x);
    }
    pub inline fn score(self: Score) isize {
        return self._copy * qc +
            self._delete * qd +
            self._boundary * qb +
            self._kill * qk +
            self._straight_acc;
    }
    fn string(self: Score, allocator: Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "\ncopy: {d}\ndelete: {d}\nboundary: {d}\nkill: {d}\nstraight_acc: {d}\nSCORE: {d}\n--------", .{
            self._copy,
            self._delete,
            self._boundary,
            self._kill,
            self._straight_acc,
            self.score(),
        });
    }
};

pub const MatchType = enum(u8) {
    // numbers are ordered in priority. The lower the number the higher the priority.
    // higher priority matches gives the result faster therefore, gives the final decision faster.
    inverse_prefix_exact = 0,
    inverse_suffix_exact = 1,

    prefix_exact = 2,
    suffix_exact = 3,

    exact = 4,
    inverse_exact = 5,

    fuzzy = 6,
};

pub fn match(text: []const u8, pattern: []const u8, is_case_sensitive: bool, match_type: MatchType) ?isize {
    const score = switch (match_type) {
        MatchType.fuzzy => fuzzyMatch(text, pattern, is_case_sensitive),
        MatchType.suffix_exact => suffixExact(text, pattern, is_case_sensitive),
        MatchType.prefix_exact => prefixExact(text, pattern, is_case_sensitive),
        else => unreachable,
    };
    return if (score) |s| s.score() else null;
}

fn fuzzyMatch(text: []const u8, pattern: []const u8, is_case_sensitive: bool) ?Score {
    var score = Score{};

    var i = text.len;
    var j = pattern.len;
    var last_pj: u8 = undefined;

    var delete_acc: isize = 0;
    var straight_acc: u5 = 0;

    var boundary_slice: ?[]const u8 = null;
    var boundary_end: usize = undefined;

    while (i > 0 and j > 0) : (i -= 1) {
        const ti = if (is_case_sensitive) text[i - 1] else std.ascii.toLower(text[i - 1]);
        const pj = if (is_case_sensitive) pattern[j - 1] else std.ascii.toLower(pattern[j - 1]);

        if (is_end_boundary(text, i - 1)) {
            boundary_end = i;
        }
        if (is_start_boundary(text, i - 1)) {
            boundary_slice = text[i - 1 .. boundary_end];
        } else {
            boundary_slice = null;
        }

        if (ti == pj) {
            score.copy();
            last_pj = pj;
            straight_acc += 1;

            if (boundary_slice) |b| {
                delete_acc = 0;
                // We don't want to give negative score if straight len is the same as boundary. i.e. full match
                if (straight_acc != b.len) {
                    score.boundary();
                }
            }

            j -= 1;
        } else if (last_pj == ti) {
            score.copy();
        } else {
            delete_acc += 1;
            // commit straight
            score.straight(straight_acc);

            straight_acc = 0;
        }

        if (boundary_slice) |_| {
            score.delete(delete_acc);
            delete_acc = 0;
        }
    }

    return if (j == 0) {
        // commit what is left + kill
        score.straight(straight_acc);
        score.delete(delete_acc);

        // calculate kill
        while (i > 0) : (i -= 1) {
            var ti = text[i - 1];
            if (in_path_sep_set(ti)) break else score.kill(1);
        }

        return score;
    } else null;
}

fn suffixExact(text: []const u8, pattern: []const u8, is_case_sensitive: bool) ?Score {
    var i = text.len;
    var j = pattern.len;
    while (i > 0 and j > 0) : (i -= 1) {
        const ti = if (is_case_sensitive) text[i - 1] else std.ascii.toLower(text[i - 1]);
        const pj = if (is_case_sensitive) pattern[j - 1] else std.ascii.toLower(pattern[j - 1]);
        if (ti == pj) {
            j -= 1;
        } else {
            break;
        }
    }

    return if (j == 0) {
        var score = Score{};
        score.copy();
        std.log.warn("t: {s} | p: {s} i: {d}", .{ text, pattern, i });
        if (i == 0) {
            // TODO: full - match
        } else if (i > 1 and is_start_boundary(text, i)) {
            score.copy();
        }
        return score;
    } else null;
}

fn prefixExact(text: []const u8, pattern: []const u8, is_case_sensitive: bool) ?Score {
    var i: usize = 0;
    var j: usize = 0;
    while (i < text.len and j < pattern.len) : (i += 1) {
        const ti = if (is_case_sensitive) text[i] else std.ascii.toLower(text[i]);
        const pj = if (is_case_sensitive) pattern[j] else std.ascii.toLower(pattern[j]);
        if (ti == pj) {
            j += 1;
        } else {
            break;
        }
    }

    return if (j == pattern.len) {
        var score = Score{};
        score.copy();
        if (i == 0) {
            // TODO: full - match
        } else if (i > 0 and is_end_boundary(text, i - 1)) {
            score.copy();
        }
        return score;
    } else null;
}

test "match" {
    const cs = true; // case-sensitive
    const ci = false; // case-insensitive
    const MT = MatchType;
    inline for (@typeInfo(MatchType).Enum.fields) |field| {
        const match_type: MatchType = @enumFromInt(field.value);

        // TODO: remove continue cases from below once implementation is done
        switch (match_type) {
            MT.inverse_exact, MT.inverse_prefix_exact, MT.inverse_suffix_exact, MT.exact => {
                continue;
            },
            else => {},
        }

        var r = match("", "", ci, match_type);
        try expect(r != null);

        r = match("", "", cs, match_type);
        try expect(r != null);

        r = match("a", "", ci, match_type);
        try expect(r != null);
        r = match("a", "", cs, match_type);
        try expect(r != null);

        r = match("", "a", ci, match_type);
        try expect(r == null);
        r = match("", "a", cs, match_type);
        try expect(r == null);

        r = match("a", "a", ci, match_type);
        try expect(r != null);
        r = match("a", "a", cs, match_type);
        try expect(r != null);

        r = match("A", "a", ci, match_type);
        try expect(r != null);
        r = match("A", "a", cs, match_type);
        try expect(r == null);

        r = match("a", "A", ci, match_type);
        try expect(r != null);
        r = match("a", "A", cs, match_type);
        try expect(r == null);

        r = match("b", "a", ci, match_type);
        try expect(r == null);
    }
}

test "fuzzy match" {
    const cs = true; // case-sensitive
    const ci = false; // case-insensitive
    const fuzzy = MatchType.fuzzy;

    var r = match("xbyaz", "ba", ci, fuzzy);
    try expect(r != null);
    r = match("xByaz", "ba", ci, fuzzy);
    try expect(r != null);
    r = match("xByaz", "ba", cs, fuzzy);
    try expect(r == null);

    r = match("xbyaz", "ab", ci, fuzzy);
    try expect(r == null);
}

test "suffix exact" {
    const cs = true; // case-sensitive
    const ci = false; // case-insensitive
    const suffix = MatchType.suffix_exact;

    var r = match("barfoo", "foo", ci, suffix);
    try expect(r != null);

    r = match("barxoo", "foo", ci, suffix);
    try expect(r == null);

    r = match("foobar", "foo", ci, suffix);
    try expect(r == null);

    r = match("barFoo", "foo", cs, suffix);
    try expect(r == null);
}
test "prefix exact" {
    const cs = true; // case-sensitive
    const ci = false; // case-insensitive
    const prefix = MatchType.prefix_exact;

    var r = match("foobar", "foo", ci, prefix);
    try expect(r != null);

    r = match("foxbar", "foo", ci, prefix);
    try expect(r == null);

    r = match("barfoo", "foo", ci, prefix);
    try expect(r == null);

    r = match("Foobar", "foo", cs, prefix);
    try expect(r == null);
}

fn in_boundary_set(ch: u8) bool {
    inline for (boundary_set) |b| {
        if (ch == b) return true;
    }
    return false;
}
fn in_path_sep_set(ch: u8) bool {
    inline for (path_separator) |s| {
        if (ch == s) return true;
    }
    return false;
}

const isLower = std.ascii.isLower;
const isUpper = std.ascii.isUpper;
fn is_start_boundary(text: []const u8, i: usize) bool {
    const current = text[i];
    if (i == 0) {
        return !in_boundary_set(current);
    }

    const prev = text[i - 1];
    return (isUpper(current) and isLower(prev)) or in_boundary_set(prev);
}
fn is_end_boundary(text: []const u8, i: usize) bool {
    const current = text[i];
    if (i == text.len - 1) {
        return !in_boundary_set(current);
    }

    const next = text[i + 1];
    return (isLower(current) and isUpper(next)) or in_boundary_set(next);
}

test "start/end boundary" {
    var s = is_start_boundary("a", 0);
    var e = is_end_boundary("a", 0);
    try expect(s and e);

    s = is_start_boundary("_", 0);
    e = is_end_boundary("_", 0);
    try expect((s or e) == false);

    s = is_start_boundary("Foo", 0);
    e = is_end_boundary("Foo", 2);
    try expect(s and e);

    s = is_start_boundary("Foo", 2);
    e = is_end_boundary("Foo", 0);
    try expect((s or e) == false);

    s = is_start_boundary("FooBar", 3);
    e = is_end_boundary("FooBar", 2);
    try expect(s and e);

    s = is_start_boundary("FooBar", 2);
    e = is_end_boundary("FooBar", 3);
    try expect((s or e) == false);

    s = is_start_boundary("foo_bar", 4);
    e = is_end_boundary("foo_bar", 2);
    try expect(s and e);

    s = is_start_boundary("foo_bar", 3);
    e = is_end_boundary("foo_bar", 3);
    try expect((s or e) == false);

    s = is_start_boundary("BaR", 2);
    e = is_end_boundary("BaR", 2);
    try expect(s and e);
}

test "fuzzy match score" {
    const cs = true; // case-sensitive
    const ci = false; // case-insensitive
    {
        var r = fuzzyMatch("foo", "a", ci);
        // TODO: full-match
        r = fuzzyMatch("Foo", "foo", cs);
    }

    { // Copy
        var r = fuzzyMatch("axy", "a", ci);
        try expect(r.?._copy == 1);
        r = fuzzyMatch("xya", "a", ci);
        try expect(r.?._copy == 1);

        r = fuzzyMatch("cbbaa", "cba", ci);
        try expect(r.?._copy == 5);
        // Last pj respect case-sensitivity
        r = fuzzyMatch("CBBAA", "cba", ci);
        try expect(r.?._copy == 5);
        r = fuzzyMatch("cbBaA", "cba", cs);
        try expect(r.?._copy == 3);
        // Last pj only counts once because search is terminated when j = 0
        r = fuzzyMatch("bbaa", "ba", ci);
        try expect(r.?._copy == 3);

        r = fuzzyMatch("baxyax", "ba", ci);
        try expect(r.?._copy == 3);
    }
    { // Straight
        const qs = Score.qs;

        var r = fuzzyMatch("a", "a", ci);
        try expect(r.?._straight_acc == qs(1));

        r = fuzzyMatch("?abc?", "abc", ci);
        try expect(r.?._straight_acc == qs(3));

        r = fuzzyMatch("?abbbccc?", "abc", ci);
        try expect(r.?._straight_acc == qs(3));

        r = fuzzyMatch("?ab?cde?", "abcde", ci);
        try expect(r.?._straight_acc == qs(2) + qs(3));

        r = fuzzyMatch("?ab_cde?", "abcde", ci);
        try expect(r.?._straight_acc == qs(2) + qs(3));
    }
    { // Delete
        var r = fuzzyMatch("?axx", "a", ci);
        try expect(r.?._delete == 2);

        r = fuzzyMatch("?bxxaxxx", "ba", ci);
        try expect(r.?._delete == 5);
    }
    { // Boundary
        var r = fuzzyMatch("_axx", "a", cs);
        try expect(r.?._delete == 0);
        try expect(r.?._boundary == 1);

        r = fuzzyMatch("_AXX", "a", ci);
        try expect(r.?._delete == 0);
        try expect(r.?._boundary == 1);

        r = fuzzyMatch("?_a_B_c", "abc", ci);
        try expect(r.?._delete == 0);
        try expect(r.?._boundary == 0);

        r = fuzzyMatch("_axx_foo", "afoo", ci);
        try expect(r.?._delete == 0);
        try expect(r.?._boundary == 1);

        r = fuzzyMatch("AxxFoo", "afoo", ci);
        try expect(r.?._delete == 0);
        try expect(r.?._boundary == 1);

        r = fuzzyMatch("AxxFoo", "AFoo", cs);
        try expect(r.?._delete == 0);
        try expect(r.?._boundary == 1);

        r = fuzzyMatch("_axx_fff", "af", ci);
        try expect(r.?._delete == 0);
        try expect(r.?._boundary == 1);

        r = fuzzyMatch("_?ax_xbx", "ab", ci);
        try expect(r.?._delete == 4);
        try expect(r.?._boundary == 0);
    }
    { // Kill
        var r = fuzzyMatch("a", "a", ci);
        try expect(r.?._kill == 0);

        r = fuzzyMatch("xxa???", "a", ci);
        try expect(r.?._kill == 2);

        r = fuzzyMatch("??/xxa???", "a", ci);
        try expect(r.?._kill == 2);
    }
}

test "exact match score" {
    const cs = true; // case-sensitive
    const ci = false; // case-insensitive

    { // suffix exact
        var r = suffixExact("foobar", "bar", ci);
        try expect(r.?.score() == 1);

        r = suffixExact("fooBAR", "BAR", cs);
        try expect(r.?.score() == 2);

        r = suffixExact("foo_bar", "bar", ci);
        try expect(r.?.score() == 2);

        r = suffixExact("bar", "bar", ci);
        // TODO: full-match
        // try expect(r.?.score() == 1);
    }
    { // prefix exact
        var r = prefixExact("foobar", "foo", ci);
        try expect(r.?.score() == 1);

        r = prefixExact("FOObar", "FOO", cs);
        try expect(r.?.score() == 1);

        r = prefixExact("foo_bar", "foo", ci);
        try expect(r.?.score() == 2);

        r = prefixExact("foo", "foo", ci);
        // TODO: full-match
        // try expect(r.?.score() == 2);
    }
}
