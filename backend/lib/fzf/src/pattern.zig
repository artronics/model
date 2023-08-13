const std = @import("std");
// TODO: import fzf_options doesn't work when running test for this file
// const options = @import("fzf_options");
const options = .{ .max_pattern_len = 64, .max_sub_pattern_size = 8 };

const Token = union(enum) {
    case_sensitive: void,
    space: void,
    single_quote: void,
    incomplete: void,

    char: u8,
};

pub fn parse(pattern: []const u8) Pattern {
    var ptrn = Pattern{};

    // Tokenizer
    var tokens: [options.max_pattern_len]Token = undefined;
    var ti: usize = 0;
    var i: usize = 0;
    while (i < pattern.len) : (i += 1) {
        const p = pattern[i];
        tokens[ti] = switch (p) {
            ' ' => Token.space,
            '\\' => blk: {
                if (i + 1 == pattern.len) break :blk Token.incomplete;
                if (pattern[i + 1] == ' ') {
                    i += 1; // consume one
                    break :blk Token{ .char = ' ' };
                } else if (pattern[i + 1] == '\'') {
                    i += 1; // consume one
                    break :blk Token{ .char = '\'' };
                }
                break :blk Token{ .char = p };
            },
            '\'' => if (i == 0 or tokens[ti - 1] == Token.space) Token.single_quote else Token{ .char = '\'' },
            else => Token{ .char = p },
        };

        ti += 1;
    }
    const token_len = ti;

    // Parser
    var chunk_no: usize = 0;
    ti = 0;
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
                Token.space => break,
                Token.single_quote => {
                    chunk.is_fuzzy = false;
                },
                Token.char => |ch| {
                    ptrn.buf[buf_i] = ch;
                    buf_i += 1;
                    chunk_size += 1;
                },
                else => {},
            }
        }
        chunk.pattern = ptrn.buf[buf_offset .. buf_offset + chunk_size];
        buf_offset += chunk_size;
        ptrn.chunks[chunk_no] = chunk;
    }

    return ptrn;
}

pub const Pattern = struct {
    buf: [options.max_pattern_len]u8 = undefined,
    sub_patterns: [options.max_sub_pattern_size][options.max_pattern_len]u8 = undefined,
    chunks: [options.max_sub_pattern_size]Chunk = undefined,

    pub const Chunk = struct {
        pattern: []const u8 = undefined,
        is_case_insensitive: bool = true,
        is_fuzzy: bool = true,
    };
};

const testing = std.testing;
const eq = testing.expectEqual;
const sliceEq = testing.expectEqualSlices;
test "pattern" {
    {
        const p = parse("foo");

        const ck = p.chunks[0];
        try sliceEq(u8, "foo", ck.pattern);
        try eq(true, ck.is_fuzzy);
        try eq(true, ck.is_case_insensitive);
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
        try eq(true, p.chunks[0].is_fuzzy);

        try sliceEq(u8, "foo", p.chunks[1].pattern);
        try eq(false, p.chunks[1].is_fuzzy);

        p = parse("' foo");
        try sliceEq(u8, "", p.chunks[0].pattern);
        try eq(false, p.chunks[0].is_fuzzy);
        try sliceEq(u8, "foo", p.chunks[1].pattern);
    }
    { // escape
        var p = parse("\\ foo\\ bar");
        try sliceEq(u8, " foo bar", p.chunks[0].pattern);

        p = parse("\\'foo\\ bar");
        try sliceEq(u8, "'foo bar", p.chunks[0].pattern);

        p = parse("a\\b");
        try sliceEq(u8, "a\\b", p.chunks[0].pattern);
    }
    { // exact match
        var p = parse("'foo");

        try eq(false, p.chunks[0].is_fuzzy);
        try sliceEq(u8, "foo", p.chunks[0].pattern);

        p = parse("fo'o");
        try eq(true, p.chunks[0].is_fuzzy);
        try sliceEq(u8, "fo'o", p.chunks[0].pattern);

        p = parse("'foo'");
        try eq(false, p.chunks[0].is_fuzzy);
        try sliceEq(u8, "foo'", p.chunks[0].pattern);
    }
    { // multi-chunk
        var p = parse("'foo 'bar");

        try eq(false, p.chunks[0].is_fuzzy);
        try sliceEq(u8, "foo", p.chunks[0].pattern);
        try eq(false, p.chunks[1].is_fuzzy);
        try sliceEq(u8, "bar", p.chunks[1].pattern);
    }
}
