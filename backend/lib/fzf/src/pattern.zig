const std = @import("std");
// TODO: import fzf_options doesn't work when running test for this file
// const options = @import("fzf_options");
const options = .{ .max_pattern_len = 64, .max_sub_pattern_size = 8 };
pub const max_pattern_len = options.max_pattern_len;

const Token = union(enum) {
    delimiter: void,
    exact_match: void,
    prefix: void,
    suffix: void,
    inverse: void,

    char: u8,
};

pub fn parse(pattern: []const u8) Pattern {
    var ptrn = Pattern{};

    const MT = Pattern.Chunk.MatchType;
    var tokens: [options.max_pattern_len]Token = undefined;
    const token_len = tokenizer(pattern, &tokens);

    var ti: usize = 0;
    var chunk_no: usize = 0;
    var buf_i: usize = 0;
    var buf_offset: usize = 0;

    while (ti < token_len) : ({
        ti += 1;
        chunk_no += 1;
    }) {
        var chunk = Pattern.Chunk{};
        var chunk_size: usize = 0;
        while (ti < token_len) : (ti += 1) {
            switch (tokens[ti]) {
                Token.delimiter => break,
                Token.exact_match => {
                    chunk.match_type = MT.exact;
                },
                Token.inverse => {
                    chunk.match_type = MT.inverse_exact;
                },
                Token.prefix => {
                    switch (chunk.match_type) {
                        MT.inverse_exact => {
                            chunk.match_type = MT.inverse_prefix_exact;
                        },
                        else => {
                            chunk.match_type = MT.prefix_exact;
                        },
                    }
                },
                Token.suffix => {
                    switch (chunk.match_type) {
                        MT.inverse_exact => {
                            chunk.match_type = MT.inverse_suffix_exact;
                        },
                        else => {
                            chunk.match_type = MT.suffix_exact;
                        },
                    }
                },
                Token.char => |ch| {
                    ptrn.buf[buf_i] = ch;
                    buf_i += 1;
                    chunk_size += 1;
                },
            }
        }
        chunk.pattern = ptrn.buf[buf_offset .. buf_offset + chunk_size];
        buf_offset += chunk_size;
        ptrn.chunks[chunk_no] = chunk;
    }

    return ptrn;
}

fn tokenizer(pattern: []const u8, tokens: []Token) usize {
    var t_len: usize = 0;
    var i: usize = 0;
    while (i < pattern.len) : (i += 1) {
        const p = pattern[i];
        tokens[t_len] = switch (p) {
            ' ' => Token.delimiter,
            '\\' => blk: {
                if (i == pattern.len - 1) break :blk Token{ .char = p };

                const chars = [_]u8{ ' ', '\'', '!', '$', '^' };
                inline for (chars) |c| {
                    if (pattern[i + 1] == c) {
                        i += 1; // consume one
                        break :blk Token{ .char = c };
                    }
                }

                break :blk Token{ .char = p };
            },
            '\'' => if (i == 0 or tokens[t_len - 1] == Token.delimiter) Token.exact_match else Token{ .char = '\'' },
            '^' => if (i == 0 or tokens[t_len - 1] == Token.delimiter or tokens[t_len - 1] == Token.inverse) Token.prefix else Token{ .char = '^' },
            '!' => if (i == 0 or tokens[t_len - 1] == Token.delimiter) Token.inverse else Token{ .char = '!' },
            '$' => if (i == pattern.len - 1 or pattern[i + 1] == ' ') Token.suffix else Token{ .char = '$' },
            else => Token{ .char = p },
        };

        t_len += 1;
    }

    return t_len;
}

pub const Pattern = struct {
    buf: [options.max_pattern_len]u8 = undefined,
    sub_patterns: [options.max_sub_pattern_size][options.max_pattern_len]u8 = undefined,
    chunks: [options.max_sub_pattern_size]Chunk = undefined,

    pub const Chunk = struct {
        pattern: []const u8 = undefined,
        is_case_insensitive: bool = true,
        match_type: MatchType = MatchType.fuzzy,

        pub const MatchType = enum {
            fuzzy,
            exact,
            prefix_exact,
            suffix_exact,
            inverse_exact,
            inverse_prefix_exact,
            inverse_suffix_exact,
        };
    };
};

const testing = std.testing;
const eq = testing.expectEqual;
const sliceEq = testing.expectEqualSlices;
test "parse pattern" {
    const MT = Pattern.Chunk.MatchType;
    {
        const p = parse("foo");

        try sliceEq(u8, "foo", p.chunks[0].pattern);
        try eq(MT.fuzzy, p.chunks[0].match_type);
        try eq(true, p.chunks[0].is_case_insensitive);
    }
    { // space -> chunk delimiter
        var p = parse("foo bar");

        try sliceEq(u8, "foo", p.chunks[0].pattern);
        try sliceEq(u8, "bar", p.chunks[1].pattern);

        p = parse(" foo");
        try sliceEq(u8, "", p.chunks[0].pattern);
        try sliceEq(u8, "foo", p.chunks[1].pattern);

        p = parse(" 'foo");
        try sliceEq(u8, "", p.chunks[0].pattern);
        try eq(MT.fuzzy, p.chunks[0].match_type);

        try sliceEq(u8, "foo", p.chunks[1].pattern);
        try eq(MT.exact, p.chunks[1].match_type);

        p = parse("' foo");
        try sliceEq(u8, "", p.chunks[0].pattern);
        try eq(MT.exact, p.chunks[0].match_type);
        try sliceEq(u8, "foo", p.chunks[1].pattern);
    }
    { // escape
        var p = parse("\\ foo\\ bar");
        try sliceEq(u8, " foo bar", p.chunks[0].pattern);

        p = parse("foo\\");
        try sliceEq(u8, "foo\\", p.chunks[0].pattern);

        p = parse("\\'foo\\ bar");
        try sliceEq(u8, "'foo bar", p.chunks[0].pattern);

        p = parse("a\\b");
        try sliceEq(u8, "a\\b", p.chunks[0].pattern);

        p = parse("\\!a");
        try sliceEq(u8, "!a", p.chunks[0].pattern);

        p = parse("\\!^a");
        try sliceEq(u8, "!^a", p.chunks[0].pattern);

        p = parse("\\^a");
        try sliceEq(u8, "^a", p.chunks[0].pattern);

        p = parse("a\\$");
        try sliceEq(u8, "a$", p.chunks[0].pattern);
    }
    { // exact match
        var p = parse("'foo");

        try eq(MT.exact, p.chunks[0].match_type);
        try sliceEq(u8, "foo", p.chunks[0].pattern);

        p = parse("fo'o");
        try eq(MT.fuzzy, p.chunks[0].match_type);
        try sliceEq(u8, "fo'o", p.chunks[0].pattern);

        p = parse("'foo'");
        try eq(MT.exact, p.chunks[0].match_type);
        try sliceEq(u8, "foo'", p.chunks[0].pattern);
    }
    { // inverse exact
        var p = parse("!foo");
        try eq(MT.inverse_exact, p.chunks[0].match_type);
        try sliceEq(u8, "foo", p.chunks[0].pattern);

        p = parse("fo!o");
        try eq(MT.fuzzy, p.chunks[0].match_type);
        try sliceEq(u8, "fo!o", p.chunks[0].pattern);
    }
    { // prefix exact
        var p = parse("^foo");
        try eq(MT.prefix_exact, p.chunks[0].match_type);
        try sliceEq(u8, "foo", p.chunks[0].pattern);

        p = parse("fo^o");
        try eq(MT.fuzzy, p.chunks[0].match_type);
        try sliceEq(u8, "fo^o", p.chunks[0].pattern);

        p = parse("^!foo");
        try eq(MT.prefix_exact, p.chunks[0].match_type);
        try sliceEq(u8, "!foo", p.chunks[0].pattern);
    }
    { // suffix exact
        var p = parse("foo$");
        try eq(MT.suffix_exact, p.chunks[0].match_type);
        try sliceEq(u8, "foo", p.chunks[0].pattern);

        p = parse("fo$o");
        try eq(MT.fuzzy, p.chunks[0].match_type);
        try sliceEq(u8, "fo$o", p.chunks[0].pattern);
    }
    { // inverse suffix exact
        var p = parse("!foo$");
        try eq(MT.inverse_suffix_exact, p.chunks[0].match_type);
        try sliceEq(u8, "foo", p.chunks[0].pattern);

        p = parse("foo!$");
        try eq(MT.suffix_exact, p.chunks[0].match_type);
        try sliceEq(u8, "foo!", p.chunks[0].pattern);
    }
    { // inverse prefix exact
        var p = parse("!^foo");
        try eq(MT.inverse_prefix_exact, p.chunks[0].match_type);
        try sliceEq(u8, "foo", p.chunks[0].pattern);
    }
    { // conflicts
        var p = parse("!^foo");
        try eq(MT.inverse_prefix_exact, p.chunks[0].match_type);
        try sliceEq(u8, "foo", p.chunks[0].pattern);
    }
    { // multi-chunk
        var p = parse("foo 'bar !baz$");

        try eq(MT.fuzzy, p.chunks[0].match_type);
        try sliceEq(u8, "foo", p.chunks[0].pattern);
        try eq(MT.exact, p.chunks[1].match_type);
        try sliceEq(u8, "bar", p.chunks[1].pattern);
        try eq(MT.inverse_suffix_exact, p.chunks[2].match_type);
        try sliceEq(u8, "baz", p.chunks[2].pattern);
    }
}
