const std = @import("std");
const time = std.time;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Search = @import("fzf.zig").Search;
const testing = std.testing;

fn lines(allocator: Allocator, comptime path: []const u8) !ArrayList([]const u8) {
    var list = try ArrayList([]const u8).initCapacity(allocator, 80000);
    const content = @embedFile(path);

    var i: usize = 0;
    var start: usize = 0;
    while (i < content.len) : (i += 1) {
        if (content[i] == '\n') {
            try list.append(content[start..i]);
            start = i + 1;
        }
    }

    return list;
}

const Result = struct {
    text: []const u8,
    score: isize,
};

pub fn sortByScore(context: void, a: Result, b: Result) bool {
    _ = context;
    return a.score > b.score;
}

test "benchmark" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const texts = try lines(a, "bench_data.txt");

    const search = Search{};
    const pattern = "drsflhled";

    var results = ArrayList(Result).init(a);

    var timer = try time.Timer.start();
    for (texts.items) |text| {
        if (try search.search(text, pattern)) |score| {
            try results.append(.{ .text = text, .score = score.score() });
        }
    }
    const lapsed = timer.lap();

    var sorted = results.toOwnedSlice();
    std.sort.sort(Result, sorted, {}, sortByScore);

    std.log.warn("\npattern: {s} *** total: {d} ** time: {d}ms\n-----------------", .{ pattern, sorted.len, lapsed / 1_000_000 });
    for (sorted) |result| {
        std.log.warn("[{d:4}] {s}", .{ result.score, result.text });
    }
}
