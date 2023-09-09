const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const testing = std.testing;
const expect = testing.expect;
const sliceEq = testing.expectEqualSlices;
// TODO: import fzf_options doesn't work when running test for this file
// const options = @import("fzf_options");
const options = .{ .max_pattern_len = 64, .max_sub_pattern_size = 8 };
pub const max_pattern_len = options.max_pattern_len;

pub const Pattern = struct {
    const Self = @This();
    const delimiter = ' ';

    arena: ArenaAllocator,
    scanner: Scanner,

    pub fn init(allocator: Allocator, pattern: []const u8) !Self {
        var arena = ArenaAllocator.init(allocator);

        const alloc = arena.allocator();
        const buf = try alloc.alloc(u8, pattern.len);
        const scanner = Scanner.init(alloc, pattern, buf);

        return .{
            .arena = arena,
            .scanner = scanner,
        };
    }

    pub fn deinit(self: Self) void {
        self.arena.deinit();
    }

    const TokenTag = enum {
        and_op,
        or_op,
        exact,
        prefix,
        suffix,
        inverse,
        text,
    };
    const Token = struct {
        tag: TokenTag,
        lexeme: ?[]const u8 = null,
    };

    const Scanner = struct {
        allocator: Allocator,
        source: []const u8,
        tokens: ArrayList(Token),

        buf: []u8,
        buf_i: usize = 0,

        start: usize = 0,
        current: usize = 0,

        fn init(allocator: Allocator, source: []const u8, buf: []u8) Scanner {
            return .{
                .allocator = allocator,
                .source = source,
                .buf = buf,
                .tokens = ArrayList(Token).init(allocator),
            };
        }
        fn deinit(s: Scanner) void {
            s.tokens.deinit();
        }
        fn scan(s: *Scanner) ![]const Token {
            while (!s.isAtEnd()) {
                try s.chunk();
                try s.operator();
            }
            return s.tokens.toOwnedSlice();
        }
        fn chunk(s: *Scanner) !void {
            if (s.match('!')) {
                try s.tokens.append(.{ .tag = TokenTag.inverse });

                if (s.match('\'')) {
                    try s.tokens.append(.{ .tag = TokenTag.exact });
                } else if (s.match('^')) {
                    try s.tokens.append(.{ .tag = TokenTag.prefix });
                }
            } else if (s.match('\'')) {
                try s.tokens.append(.{ .tag = TokenTag.exact });
            } else if (s.match('^')) {
                try s.tokens.append(.{ .tag = TokenTag.prefix });
            } else if (s.peek() == '\\' and (s.peekNext() == '\'' or s.peekNext() == '^' or s.peekNext() == '!')) {
                _ = s.advance();
            }
            try s.matchText();
        }
        fn operator(s: *Scanner) !void {
            if (s.match(' ')) {
                if (s.peek() != '|') {
                    try s.tokens.append(.{ .tag = TokenTag.and_op });
                } else if (s.peek() == '|' and s.peekNext() == delimiter) {
                    try s.tokens.append(.{ .tag = TokenTag.or_op });
                    _ = s.advance();
                    _ = s.advance();
                }
            }
        }
        fn matchText(s: *Scanner) !void {
            const start = s.current;
            while (!s.isAtEnd() and s.peek() != delimiter and
                !(s.peek() == '$' and (s.peekNext() == delimiter or s.peekNext() == 0)))
            {
                _ = s.advance();
            }
            try s.tokens.append(.{ .tag = TokenTag.text, .lexeme = s.source[start..s.current] });

            if (s.match('$')) {
                try s.tokens.append(.{ .tag = TokenTag.suffix });
            }
        }

        fn advance(s: *Scanner) u8 {
            const ch = s.source[s.current];
            s.current += 1;

            return ch;
        }
        fn match(s: *Scanner, expected: u8) bool {
            if (s.isAtEnd()) return false;
            if (s.source[s.current] != expected) return false;

            s.current += 1;

            return true;
        }
        fn peek(s: *Scanner) u8 {
            if (s.isAtEnd()) return 0;
            return s.source[s.current];
        }
        fn peekNext(s: *Scanner) u8 {
            if (s.current + 1 >= s.source.len) return 0;
            return s.source[s.current + 1];
        }
        fn isAtEnd(s: *Scanner) bool {
            return s.current >= s.source.len;
        }

        test "Scanner" {
            const a = testing.allocator;
            var buf = try a.alloc(u8, 1024);
            defer a.free(buf);
            {
                const pattern = "foo bar | baz";
                var s = Scanner.init(a, pattern, buf);
                defer s.deinit();

                const tokens = try s.scan();
                defer a.free(tokens);

                try expect(tokens[0].tag == TokenTag.text);
                try sliceEq(u8, "foo", tokens[0].lexeme.?);
            }
            {
                const pattern = "!'foo !^bar$ !bax | ^baz$";
                var s = Scanner.init(a, pattern, buf);
                defer s.deinit();

                const tokens = try s.scan();
                defer a.free(tokens);

                try expect(tokens[0].tag == TokenTag.inverse);
                try expect(tokens[1].tag == TokenTag.exact);
                try expect(tokens[2].tag == TokenTag.text);
                try sliceEq(u8, "foo", tokens[2].lexeme.?);
                try expect(tokens[3].tag == TokenTag.and_op);
                try expect(tokens[4].tag == TokenTag.inverse);
                try expect(tokens[5].tag == TokenTag.prefix);
                try sliceEq(u8, "bar", tokens[6].lexeme.?);
                try expect(tokens[7].tag == TokenTag.suffix);
                try expect(tokens[8].tag == TokenTag.and_op);
                try expect(tokens[9].tag == TokenTag.inverse);
                try expect(tokens[10].tag == TokenTag.text); // bax
                try expect(tokens[11].tag == TokenTag.or_op);
                try expect(tokens[12].tag == TokenTag.prefix);
                try expect(tokens[13].tag == TokenTag.text); // baz
                try expect(tokens[14].tag == TokenTag.suffix);
            }
        }
        test "Scanner scape" {
            const a = testing.allocator;
            var buf = try a.alloc(u8, 1024);
            defer a.free(buf);

            const pattern = "\\!foo\\ bar";
            var s = Scanner.init(a, pattern, buf);
            defer s.deinit();

            const tokens = try s.scan();
            defer a.free(tokens);

            try expect(tokens[0].tag == TokenTag.text);
            try sliceEq(u8, "!foo bar", tokens[0].lexeme.?);
        }
    };
};

test "pattern" {
    const a = testing.allocator;
    const pattern = "foo bar";
    const p = try Pattern.init(a, pattern);
    defer p.deinit();

    try expect(true);
}
