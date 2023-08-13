const std = @import("std");
// TODO: import fzf_options doesn't work when running test for this file
// const options = @import("fzf_options");
const options = .{ .max_pattern_len = 64, .max_sub_pattern_size = 8 };

pub const Pattern = struct {
    pattern_buf: [options.max_pattern_len]u8 = undefined,
    sub_patterns: [options.max_sub_pattern_size][options.max_pattern_len]u8 = undefined,
    chunks: [options.max_sub_pattern_size]Chunk = undefined,

    pub const Chunk = struct {
        pattern: []const u8 = undefined,
        is_case_insensitive: bool = true,
        is_fuzzy: bool = true,
    };

    const Self = @This();
    pub fn init() Self {
        return .{};
    }

    fn parse(self: *Self, pattern: []const u8) void {
        var pi: usize = 0;
        var sub_pi: usize = 0;

        while (pi < pattern.len) : (pi += 1) {
            // self.pattern_buf[pi] = pattern[pi];

            var chunk_ch_i: usize = 0;
            var chunk_offset = pi;
            var chunk = Chunk{};

            while (pi < pattern.len and pattern[pi] != ' ') : ({
                pi += 1;
                chunk_ch_i += 1;
            }) {
                self.pattern_buf[chunk_offset + chunk_ch_i] = pattern[pi];
            }
            chunk.pattern = self.pattern_buf[chunk_offset..chunk_offset + chunk_ch_i];

            self.chunks[sub_pi] = chunk;
            sub_pi += 1;
        }
    }
};

const testing = std.testing;
const eq = testing.expectEqual;
const sliceEq = testing.expectEqualSlices;
test "pattern" {
    var p = Pattern.init();
    {
        const pattern = "foo";
        p.parse(pattern);

        const ck = p.chunks[0];
        try sliceEq(u8, pattern, ck.pattern);
        try eq(true, ck.is_fuzzy);
        try eq(true, ck.is_case_insensitive);
    }
    {
        const pattern = "foo bar";
        p.parse(pattern);

        try sliceEq(u8, "foo", p.chunks[0].pattern);
        try sliceEq(u8, "bar", p.chunks[1].pattern);
    }
}
