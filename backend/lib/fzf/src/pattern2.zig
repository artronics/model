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

const BinExpr = struct {
    l: *Expr,
    r: *Expr,

    fn string(e: BinExpr, alloc: Allocator, str: *ArrayList(u8)) !void {
        try e.l.string(alloc, str);
        try str.append(' ');
        try e.r.string(alloc, str);
        try str.append(')');
    }
};
const Expr = union(enum) {
    and_op: BinExpr,
    or_op: BinExpr,
    chunk: Chunk,

    fn string(e: Expr, alloc: Allocator, str: *ArrayList(u8)) Allocator.Error!void {
        switch (e) {
            Expr.and_op => |op| {
                try str.appendSlice("(and ");
                try op.string(alloc, str);
            },
            Expr.or_op => |op| {
                try str.appendSlice("(or ");
                try op.string(alloc, str);
            },
            Expr.chunk => |chunk| {
                const s = try chunk.allocPrint(alloc);
                defer alloc.free(s);
                try str.appendSlice(s);
            },
        }
    }
};
const Chunk = struct {
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

pub const Pattern = struct {
    expr: Expr,

    fn allocPrint(pattern: Pattern, alloc: Allocator) ![]const u8 {
        var string = ArrayList(u8).init(alloc);
        defer string.deinit();
        try pattern.expr.string(alloc, &string);

        return string.toOwnedSlice();
    }
};

test "pattern" {
    const a = testing.allocator;
    const pattern = "foo bar";
    const buf = try a.alloc(u8, pattern.len);
    defer a.free(buf);

    const tokens = blk: {
        var scanner = Scanner.init(a, pattern, buf);
        defer scanner.deinit();
        break :blk try scanner.scan();
    };
    defer a.free(tokens);

    const parser = Parser.init(a, tokens);
    defer parser.deinit();
}

const ParseError = error{InsufficientToken};

const Parser = struct {
    const Self = @This();

    arena: ArenaAllocator,
    tokens: []const Token,
    current: usize = 0,

    fn init(allocator: Allocator, tokens: []const Token) Self {
        var arena = ArenaAllocator.init(allocator);

        return .{
            .arena = arena,
            .tokens = tokens,
        };
    }

    fn deinit(self: Self) void {
        self.arena.deinit();
    }

    fn parse(self: *Self) !Pattern {
        const exp = try self.expr();
        return Pattern{ .expr = exp };
    }

    fn expr(self: *Self) !Expr {
        return self.andExpr();
    }

    // andExpr -> orExpr (<space> orExpr)*
    fn andExpr(self: *Self) !Expr {
        var lhs = try self.orExpr();
        while (self.match(&.{Tag.and_op})) {
            const alloc = self.arena.allocator();
            var l = try alloc.create(Expr);
            errdefer alloc.destroy(l);
            l.* = lhs;

            const rhs = try self.orExpr();
            var r = try alloc.create(Expr);
            errdefer alloc.destroy(r);
            r.* = rhs;

            lhs = Expr{ .and_op = BinExpr{ .l = l, .r = r } };
        }

        return lhs;
    }
    // orExpr -> chunk ( | chunk)*
    fn orExpr(self: *Self) !Expr {
        var lhs = try self.chunk();
        while (self.match(&.{Tag.or_op})) {
            const alloc = self.arena.allocator();
            var l = try alloc.create(Expr);
            errdefer alloc.destroy(l);
            l.* = lhs;

            const rhs = try self.chunk();
            var r = try alloc.create(Expr);
            errdefer alloc.destroy(r);
            r.* = rhs;

            lhs = Expr{ .or_op = BinExpr{ .l = l, .r = r } };
        }

        return lhs;
    }

    // chunk -> !?^?TEXT$?
    fn chunk(self: *Self) !Expr {
        if (self.match(&.{ Tag.exact, Tag.inverse, Tag.prefix, Tag.suffix, Tag.text })) {
            var chk = Chunk{};
            const prev = self.previous();
            switch (prev.tag) {
                Tag.text => {
                    chk.pattern = prev.lexeme.?;
                },
                Tag.exact => {
                    chk.match_type = Chunk.MatchType.exact;
                    const text = self.consume(Tag.text, "expected text; fallback to empty string") catch Token{ .tag = Tag.text, .lexeme = "" };
                    chk.pattern = text.lexeme.?;
                },
                Tag.inverse => {
                    if (self.peek().tag == Tag.text) {
                        chk.match_type = Chunk.MatchType.inverse_exact;
                    } else if (self.peek().tag == Tag.prefix) {
                        chk.match_type = Chunk.MatchType.inverse_exact;
                        _ = self.advance();
                    }
                    const text = self.consume(Tag.text, "expected text; fallback to empty string") catch Token{ .tag = Tag.text, .lexeme = "" };
                    chk.pattern = text.lexeme.?;
                    if (self.peek().tag == Tag.suffix) {
                        // FIXME: !^foo$ makes no sense. Yet here, if this happened we'll ignore the prefix and instead use the suffix
                        // What is the right behaviour?
                        chk.match_type = Chunk.MatchType.inverse_suffix_exact;
                        _ = self.advance();
                    }
                },
                else => unreachable,
            }
            return Expr{ .chunk = chk };
        }
        return ParseError.InsufficientToken;
    }
    fn advance(self: *Self) Token {
        if (!self.isAtEnd()) self.current += 1;
        return self.previous();
    }

    fn match(self: *Self, tags: []const Tag) bool {
        for (tags) |tag| {
            if (self.check(tag)) {
                _ = self.advance();
                return true;
            }
        }
        return false;
    }

    fn check(self: *Self, tag: Tag) bool {
        // FIXME: below is unnecessary and, it fails given tag=Eof
        if (self.isAtEnd()) return false;
        return self.peek().tag == tag;
    }

    fn isAtEnd(self: *Self) bool {
        return self.current >= self.tokens.len;
    }

    fn peek(self: *Self) Token {
        return self.tokens[self.current];
    }

    fn previous(self: *Self) Token {
        return self.tokens[self.current - 1];
    }

    fn consume(self: *Self, tag: Tag, msg: []const u8) !Token {
        if (self.check(tag)) return self.advance();
        std.log.warn("Unexpected token: {s}", .{msg});
        return ParseError.InsufficientToken;
    }

    test "parser" {
        const a = testing.allocator;
        // ^foo | !bar !baz$ -> (and (or 'foo !bar) !baz$)
        const tokens = [_]Token{
            .{ .tag = Tag.exact },
            .{ .tag = Tag.text, .lexeme = "foo" },

            .{ .tag = Tag.or_op },

            .{ .tag = Tag.inverse },
            .{ .tag = Tag.text, .lexeme = "bar" },

            .{ .tag = Tag.and_op },

            .{ .tag = Tag.inverse },
            .{ .tag = Tag.text, .lexeme = "baz" },
            .{ .tag = Tag.suffix },
        };
        var parser = Parser.init(a, &tokens);
        defer parser.deinit();

        const pattern = try parser.parse();
        const str = try pattern.allocPrint(a);
        defer a.free(str);
        std.log.warn("{s}", .{str});

        const and_expr = pattern.expr.and_op;
        // right
        try sliceEq(u8, "baz", and_expr.r.chunk.pattern);
        try expect(and_expr.r.chunk.match_type == Chunk.MatchType.inverse_suffix_exact);
        // left
        const or_expr = and_expr.l.or_op;
        try sliceEq(u8, "foo", or_expr.l.chunk.pattern);
        try expect(or_expr.l.chunk.match_type == Chunk.MatchType.exact);

        try sliceEq(u8, "bar", or_expr.r.chunk.pattern);
        try expect(or_expr.r.chunk.match_type == Chunk.MatchType.inverse_exact);
    }
};

const Tag = enum {
    and_op,
    or_op,
    exact,
    prefix,
    suffix,
    inverse,
    text,
    eof,
};
const Token = struct {
    tag: Tag,
    lexeme: ?[]const u8 = null,
};

const Scanner = struct {
    const delimiter = ' ';

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
            try s.tokens.append(.{ .tag = Tag.inverse });

            if (s.match('\'')) {
                try s.tokens.append(.{ .tag = Tag.exact });
            } else if (s.match('^')) {
                try s.tokens.append(.{ .tag = Tag.prefix });
            }
        } else if (s.match('\'')) {
            try s.tokens.append(.{ .tag = Tag.exact });
        } else if (s.match('^')) {
            try s.tokens.append(.{ .tag = Tag.prefix });
        } else if (s.peek() == '\\' and (s.peekNext() == '\'' or s.peekNext() == '^' or s.peekNext() == '!')) {
            _ = s.advance();
        }
        try s.matchText();
    }
    fn operator(s: *Scanner) !void {
        if (s.match(' ')) {
            if (s.peek() != '|') {
                try s.tokens.append(.{ .tag = Tag.and_op });
            } else if (s.peek() == '|' and s.peekNext() == delimiter) {
                try s.tokens.append(.{ .tag = Tag.or_op });
                _ = s.advance();
                _ = s.advance();
            }
        }
    }
    fn matchText(s: *Scanner) !void {
        const start = s.buf_i;
        var has_suffix = false;

        // break until under:  "foo", "foo ", "foo$", "foo$ " and account for escape: "foo\$", "foo\ bar" etc
        while (!s.isAtEnd()) {
            if (s.peek() == '\\' and (s.peekNext() == ' ' or s.peekNext() == '$')) {
                _ = s.advance();
                s.buf[s.buf_i] = s.advance();
                s.buf_i += 1;
            } else if (s.peek() == '$' and (s.peekNext() == delimiter or s.peekNext() == 0)) {
                _ = s.advance();
                has_suffix = true;
                break;
            } else if (s.peek() == delimiter) {
                break;
            } else {
                s.buf[s.buf_i] = s.advance();
                s.buf_i += 1;
            }
        }
        try s.tokens.append(.{ .tag = Tag.text, .lexeme = s.buf[start..s.buf_i] });
        if (has_suffix) {
            try s.tokens.append(.{ .tag = Tag.suffix });
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
            const pattern = "";
            var s = Scanner.init(a, pattern, buf);
            defer s.deinit();

            const tokens = try s.scan();
            defer a.free(tokens);

            try expect(tokens.len == 0);
        }
        {
            const pattern = "foobar";
            var s = Scanner.init(a, pattern, buf);
            defer s.deinit();

            const tokens = try s.scan();
            defer a.free(tokens);

            try expect(tokens[0].tag == Tag.text);
            try sliceEq(u8, "foobar", tokens[0].lexeme.?);
        }
        {
            const pattern = "foo bar | baz";
            var s = Scanner.init(a, pattern, buf);
            defer s.deinit();

            const tokens = try s.scan();
            defer a.free(tokens);

            try expect(tokens[0].tag == Tag.text);
            try sliceEq(u8, "foo", tokens[0].lexeme.?);

            try expect(tokens[1].tag == Tag.and_op);

            try expect(tokens[2].tag == Tag.text);
            try sliceEq(u8, "bar", tokens[2].lexeme.?);

            try expect(tokens[3].tag == Tag.or_op);

            try expect(tokens[4].tag == Tag.text);
            try sliceEq(u8, "baz", tokens[4].lexeme.?);
        }
        {
            const pattern = "!'foo !^bar$ !bax | ^!baz$";
            var s = Scanner.init(a, pattern, buf);
            defer s.deinit();

            const tokens = try s.scan();
            defer a.free(tokens);

            try expect(tokens[0].tag == Tag.inverse);
            try expect(tokens[1].tag == Tag.exact);
            try expect(tokens[2].tag == Tag.text);
            try sliceEq(u8, "foo", tokens[2].lexeme.?);
            try expect(tokens[3].tag == Tag.and_op);
            try expect(tokens[4].tag == Tag.inverse);
            try expect(tokens[5].tag == Tag.prefix);
            try sliceEq(u8, "bar", tokens[6].lexeme.?);
            try expect(tokens[7].tag == Tag.suffix);
            try expect(tokens[8].tag == Tag.and_op);
            try expect(tokens[9].tag == Tag.inverse);
            try expect(tokens[10].tag == Tag.text); // bax
            try expect(tokens[11].tag == Tag.or_op);
            try expect(tokens[12].tag == Tag.prefix);
            try expect(tokens[13].tag == Tag.text);
            try sliceEq(u8, "!baz", tokens[13].lexeme.?); // ! after match_type is just character
            try expect(tokens[14].tag == Tag.suffix);
        }
    }
    test "Scanner escape" {
        const a = testing.allocator;
        var buf = try a.alloc(u8, 1024);
        defer a.free(buf);

        const pattern = "\\!foo\\ bar\\$\\ ^bax\\ |\\ baz";
        var s = Scanner.init(a, pattern, buf);
        defer s.deinit();

        const tokens = try s.scan();
        defer a.free(tokens);

        try expect(tokens[0].tag == Tag.text);
        try sliceEq(u8, "!foo bar$ ^bax | baz", tokens[0].lexeme.?);
    }
};
