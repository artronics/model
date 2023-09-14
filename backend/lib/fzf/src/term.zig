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
const max_pattern_len = options.max_pattern_len;

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
pub const Expr = union(enum) {
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
pub const Chunk = struct {
    pattern: []const u8 = undefined,
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

pub const Term = struct {
    arena: ArenaAllocator,
    expr: Expr = undefined,
    buf: []u8 = undefined,

    pub fn init(allocator: Allocator) Term {
        return .{ .arena = ArenaAllocator.init(allocator) };
    }
    pub fn deinit(self: Term) void {
        self.arena.deinit();
    }

    pub fn parse(self: *Term, pattern: []const u8) !void {
        const alloc = self.arena.allocator();
        self.buf = try alloc.alloc(u8, pattern.len);

        var scanner = Scanner.init(alloc, pattern, self.buf);
        defer scanner.deinit();
        const tokens = try scanner.scan();

        var parser = Parser.init(alloc, tokens);

        self.expr = try parser.parse();
    }

    fn allocPrint(pattern: Term, alloc: Allocator) ![]const u8 {
        var string = ArrayList(u8).init(alloc);
        defer string.deinit();
        try pattern.expr.string(alloc, &string);

        return string.toOwnedSlice();
    }
};

test "pattern" {
    const a = testing.allocator;
    var pattern = Term.init(a);
    defer pattern.deinit();

    {
        try pattern.parse("foo bar");

        try sliceEq(u8, "foo", pattern.expr.and_op.l.chunk.pattern);
        try sliceEq(u8, "bar", pattern.expr.and_op.r.chunk.pattern);
    }
    {
        try pattern.parse("baz | bax");

        try sliceEq(u8, "baz", pattern.expr.or_op.l.chunk.pattern);
        try sliceEq(u8, "bax", pattern.expr.or_op.r.chunk.pattern);
    }
    {
        try pattern.parse("foobar");
        try sliceEq(u8, "foobar", pattern.expr.chunk.pattern);
    }
}
test "pattern handling errors" {
    const a = testing.allocator;
    var pattern = Term.init(a);
    defer pattern.deinit();

    // Insufficient tokens should produce an empty chunk with default fields
    {
        try pattern.parse("foo | ");

        try expect(Expr.or_op == pattern.expr);
        try sliceEq(u8, "foo", pattern.expr.or_op.l.chunk.pattern);

        try sliceEq(u8, "", pattern.expr.or_op.r.chunk.pattern);
        try expect(Chunk.MatchType.fuzzy == pattern.expr.or_op.r.chunk.match_type);
    }
    {
        try pattern.parse("bar ");

        try expect(Expr.and_op == pattern.expr);
        try sliceEq(u8, "bar", pattern.expr.and_op.l.chunk.pattern);

        try sliceEq(u8, "", pattern.expr.and_op.r.chunk.pattern);
        try expect(Chunk.MatchType.fuzzy == pattern.expr.and_op.r.chunk.match_type);
    }
    // Pending for chunk shouldn't cause errors, instead should assume empty string
    {
        try pattern.parse("!");

        try expect(Expr.chunk == pattern.expr);
        try sliceEq(u8, "", pattern.expr.chunk.pattern);
        try expect(Chunk.MatchType.inverse_exact == pattern.expr.chunk.match_type);
    }
    {
        try pattern.parse("!^");

        try expect(Expr.chunk == pattern.expr);
        try sliceEq(u8, "", pattern.expr.chunk.pattern);
        try expect(Chunk.MatchType.inverse_prefix_exact == pattern.expr.chunk.match_type);
    }
    {
        try pattern.parse("!$");

        try expect(Expr.chunk == pattern.expr);
        try sliceEq(u8, "", pattern.expr.chunk.pattern);
        try expect(Chunk.MatchType.inverse_suffix_exact == pattern.expr.chunk.match_type);
    }
}

const ParseError = error{InsufficientToken};

const Parser = struct {
    const Self = @This();

    allocator: Allocator,
    tokens: []const Token,
    current: usize = 0,

    fn init(allocator: Allocator, tokens: []const Token) Self {
        return .{
            .allocator = allocator,
            .tokens = tokens,
        };
    }

    fn parse(self: *Self) !Expr {
        return self.expr();
    }

    fn expr(self: *Self) !Expr {
        return self.andExpr();
    }

    // andExpr -> orExpr (<space> orExpr)*
    fn andExpr(self: *Self) !Expr {
        var lhs = try self.orExpr();

        while (self.matchAny(&.{Tag.and_op})) {
            var l = try self.allocator.create(Expr);
            errdefer self.allocator.destroy(l);
            l.* = lhs;

            const rhs = try self.orExpr();
            var r = try self.allocator.create(Expr);
            errdefer self.allocator.destroy(r);
            r.* = rhs;

            lhs = Expr{ .and_op = BinExpr{ .l = l, .r = r } };
        }

        return lhs;
    }
    // orExpr -> chunk ( | chunk)*
    fn orExpr(self: *Self) !Expr {
        var lhs = self.chunk();

        while (self.matchAny(&.{Tag.or_op})) {
            var l = try self.allocator.create(Expr);
            errdefer self.allocator.destroy(l);
            l.* = lhs;

            const rhs = self.chunk();
            var r = try self.allocator.create(Expr);
            errdefer self.allocator.destroy(r);
            r.* = rhs;

            lhs = Expr{ .or_op = BinExpr{ .l = l, .r = r } };
        }

        return lhs;
    }

    // chunk -> !?^?TEXT$?
    fn chunk(self: *Self) Expr {
        if (self.matchAny(&.{ Tag.exact, Tag.inverse, Tag.prefix, Tag.suffix, Tag.text })) {
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
                    if (self.match(Tag.text)) {
                        chk.match_type = Chunk.MatchType.inverse_exact;
                    } else if (self.match(Tag.prefix)) {
                        chk.match_type = Chunk.MatchType.inverse_prefix_exact;
                        _ = self.advance();
                    }
                    const text = self.consume(Tag.text, "expected text; fallback to empty string") catch Token{ .tag = Tag.text, .lexeme = "" };
                    chk.pattern = text.lexeme.?;
                    if (self.match(Tag.suffix)) {
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
        return .{ .chunk = .{} };
    }
    fn advance(self: *Self) Token {
        if (!self.isEof()) self.current += 1;
        return self.previous();
    }

    fn matchAny(self: *Self, tags: []const Tag) bool {
        for (tags) |tag| {
            if (self.match(tag)) {
                _ = self.advance();
                return true;
            }
        }
        return false;
    }

    fn match(self: *Self, tag: Tag) bool {
        return self.tokens[self.current].tag == tag;
    }

    fn isEof(self: *Self) bool {
        return self.tokens[self.current].tag == Tag.eof;
    }

    fn previous(self: *Self) Token {
        return self.tokens[self.current - 1];
    }

    fn consume(self: *Self, tag: Tag, msg: []const u8) !Token {
        if (self.match(tag)) return self.advance();
        std.log.warn("Unexpected token: {s}", .{msg});
        return ParseError.InsufficientToken;
    }

    test "parser" {
        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        // ^foo | !bar !baz$ | !^bax ->  (and (or 'foo !bar) (or !baz$ !^bax))
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

            .{ .tag = Tag.or_op },

            .{ .tag = Tag.inverse },
            .{ .tag = Tag.prefix },
            .{ .tag = Tag.text, .lexeme = "bax" },

            .{ .tag = Tag.eof },
        };
        var parser = Parser.init(arena.allocator(), &tokens);

        const exp = try parser.parse();

        const and_expr = exp.and_op;
        // left
        const l_or = and_expr.l.or_op;
        try sliceEq(u8, "foo", l_or.l.chunk.pattern);
        try expect(l_or.l.chunk.match_type == Chunk.MatchType.exact);

        try sliceEq(u8, "bar", l_or.r.chunk.pattern);
        try expect(l_or.r.chunk.match_type == Chunk.MatchType.inverse_exact);
        // right
        const r_or = and_expr.r.or_op;
        try sliceEq(u8, "baz", r_or.l.chunk.pattern);
        try expect(r_or.l.chunk.match_type == Chunk.MatchType.inverse_suffix_exact);

        try sliceEq(u8, "bax", r_or.r.chunk.pattern);
        try expect(r_or.r.chunk.match_type == Chunk.MatchType.inverse_prefix_exact);
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
        while (!s.isEof()) {
            try s.chunk();
            try s.operator();
        }
        try s.tokens.append(.{ .tag = Tag.eof });
        return s.tokens.items;
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
        while (!s.isEof()) {
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
        if (s.isEof()) return false;
        if (s.source[s.current] != expected) return false;

        s.current += 1;

        return true;
    }
    fn peek(s: *Scanner) u8 {
        if (s.isEof()) return 0;
        return s.source[s.current];
    }
    fn peekNext(s: *Scanner) u8 {
        if (s.current + 1 >= s.source.len) return 0;
        return s.source[s.current + 1];
    }
    fn isEof(s: *Scanner) bool {
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

            try expect(tokens[0].tag == Tag.eof);
        }
        {
            const pattern = "foobar";
            var s = Scanner.init(a, pattern, buf);
            defer s.deinit();

            const tokens = try s.scan();

            try expect(tokens[0].tag == Tag.text);
            try sliceEq(u8, "foobar", tokens[0].lexeme.?);
        }
        {
            const pattern = "foo bar | baz";
            var s = Scanner.init(a, pattern, buf);
            defer s.deinit();

            const tokens = try s.scan();

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

        try expect(tokens[0].tag == Tag.text);
        try sliceEq(u8, "!foo bar$ ^bax | baz", tokens[0].lexeme.?);
    }
};
