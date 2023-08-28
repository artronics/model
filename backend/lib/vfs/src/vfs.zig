const std = @import("std");
const fs = std.fs;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const testing = std.testing;
const eq = std.testing.expectEqual;

const VFile = struct {
    const Kind = fs.File.Kind;

    path: []const u8,
    children: *ArrayList(VFile),
    parent: ?*VFile,
    kind: Kind,

    fn init(allocator: Allocator, path: []const u8, kind: Kind) !VFile {
        var children = try allocator.create(ArrayList(VFile));
        children.* = ArrayList(VFile).init(allocator);

        return VFile{
            .path = path,
            .children = children,
            .parent = null,
            .kind = kind,
        };
    }

    fn addChild(self: *VFile, node: *VFile) !void {
        node.parent = self;
        try self.children.append(node.*);
    }

    fn print(self: VFile, string: *ArrayList(u8)) !void {
        var parent = self.parent;
        var indent: u8 = 0;
        while (parent != null) : (parent = parent.?.parent) {
            indent += 1;
        }

        for (0..indent) |_| {
            try string.appendSlice("  ");
        }
        if (self.kind == Kind.directory) {
            try string.append('/');
            try string.appendSlice(fs.path.basename(self.path));
        } else {
            try string.appendSlice(fs.path.basename(self.path));
        }
        try string.append('\n');

        for (self.children.items) |child| {
            try child.print(string);
        }
    }

    test "VFile" {
        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var root = try VFile.init(alloc, "root", Kind.directory);
        {
            var a = try VFile.init(alloc, "a", Kind.directory);
            var b = try VFile.init(alloc, "b", Kind.directory);
            var c = try VFile.init(alloc, "c", Kind.directory);
            try root.addChild(&a);
            try root.addChild(&b);
            try b.addChild(&c);
        }

        var string = ArrayList(u8).init(alloc);
        try root.print(&string);
        const exp_out =
            \\/root
            \\  /a
            \\  /b
            \\    /c
            \\
        ;
        try testing.expectEqualSlices(u8, exp_out, string.items);
    }
};

const Vfs = struct {
    const Self = @This();

    arena: ArenaAllocator,
    root: VFile,
    path_buf: PathBuffer,

    pub fn init(allocator: Allocator, path: []const u8) !Self {
        var arena = ArenaAllocator.init(allocator);
        const arenaAlloc = arena.allocator();

        var d = try fs.openDirAbsolute(path, .{ .access_sub_paths = true, .no_follow = true });
        defer d.close();
        const id = fs.IterableDir{ .dir = d };
        var walker = try id.walk(arenaAlloc);
        defer walker.deinit();

        const root_path = try std.fmt.allocPrint(arenaAlloc, "{s}", .{std.fs.path.basename(path)});
        var root = try VFile.init(arenaAlloc, root_path, VFile.Kind.directory);
        try walkDirs(arenaAlloc, &walker, &root);

        return Self{
            .arena = arena,
            .root = root,
            .path_buf = try PathBuffer.init(arenaAlloc),
        };
    }
    pub fn deinit(self: Self) void {
        self.arena.deinit();
    }
    fn walkDirs(allocator: Allocator, walker: *fs.IterableDir.Walker, root: *VFile) !void {
        var stack = ArrayList(*VFile).init(allocator);
        defer stack.deinit();

        try stack.append(root);

        while (try walker.next()) |next| {
            var node = try allocator.create(VFile);
            const path = try std.fmt.allocPrint(allocator, "{s}", .{next.path});
            node.* = try VFile.init(allocator, path, next.kind);

            const node_parent = fs.path.dirname(node.path) orelse root.path;

            var top = stack.pop();
            while (!std.mem.eql(u8, top.path, node_parent)) {
                top = stack.pop();
            }
            try stack.append(top);
            try stack.append(node);
            try top.addChild(node);

            // TODO: Below is an unrolled version of above when same level child are added. Does it perform better?
            //       In most real world scenarios the number of files at the same level will be bigger than the number of directories
            //
            // var top = stack.getLast();
            // if (std.mem.eql(u8, top.path, node_parent)) {
            //     try top.addChild(node);
            //     try stack.append(node);
            // } else {
            //     top = stack.pop();
            //     while (!std.mem.eql(u8, top.path, node_parent)) {
            //         top = stack.pop();
            //     }
            //     try stack.append(top);
            //     try stack.append(node);
            //     try top.addChild(node);
            // }
        }
    }
    /// buffer used for storing paths
    /// it doesn't store a reference to the allocated memory i.e. it leaks memory. Only use it with ArenaAllocator.
    // TODO: Probably using an ArrayList with adjusting all pointers' offset in case of realloc is a better choice?
    const PathBuffer = struct {
        allocator: Allocator,
        cur_buf: []u8 = undefined,
        cur_index: usize = 0,

        const cap: usize = 1024;

        fn init(allocator: Allocator) !PathBuffer {
            var self = PathBuffer{ .allocator = allocator };
            self.cur_buf = try allocator.alloc(u8, cap);

            return self;
        }

        fn appendSlice(ss: *PathBuffer, s: []const u8) ![]const u8 {
            const left = cap - ss.cur_index;
            if (s.len > left) {
                ss.cur_buf = try ss.allocator.alloc(u8, cap);
                ss.cur_index = 0;
            }

            const offset = ss.cur_index;
            var i: usize = 0;
            while (i < s.len) : ({
                i += 1;
                ss.cur_index += 1;
            }) {
                ss.cur_buf[ss.cur_index] = s[i];
            }

            return ss.cur_buf[offset .. offset + s.len];
        }
    };

    test "PathBuffer" {
        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();

        var ss = try PathBuffer.init(arena.allocator());
        const exp_x = "x" ** PathBuffer.cap;
        const exp_y = "y" ** PathBuffer.cap;

        const sx = try ss.appendSlice(exp_x);
        const sy = try ss.appendSlice(exp_y);
        const foo = try ss.appendSlice("foo");
        const bar = try ss.appendSlice("bar");

        try testing.expectEqualSlices(u8, exp_x, sx);
        try testing.expectEqualSlices(u8, exp_y, sy);
        try testing.expectEqualSlices(u8, "foo", foo);
        try testing.expectEqualSlices(u8, "bar", bar);
    }
};

test "vfs" {
    const a = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    try makeTestData(tmp_dir);

    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    var d = try tmp_dir.dir.realpath("root", &buf);

    const vfs = try Vfs.init(a, d);
    defer vfs.deinit();
    std.log.warn("path: {s}", .{vfs.root.path});

    var string = try ArrayList(u8).initCapacity(a, 4096);
    defer string.deinit();
    try string.append('\n');
    try vfs.root.print(&string);

    std.log.warn("{s}", .{string.items});

    try assertFs(&vfs.root);
}

/// create a simple nested directory structure for testing
/// /root
///   /empty
///   /a
///     /b
///       c.txt
///   b.txt
///   /c
///     c1.txt
///     c2.txt
///   /same
///     /same
///       /same
///
fn makeTestData(dir: testing.TmpDir) !void {
    try dir.dir.makePath("root/empty");
    try dir.dir.makePath("root/a/b");
    try dir.dir.makePath("root/c");
    try dir.dir.makePath("root/same/same/same");
    _ = try dir.dir.createFile("root/b.txt", .{});
    _ = try dir.dir.createFile("root/c/c1.txt", .{});
    _ = try dir.dir.createFile("root/c/c2.txt", .{});
    _ = try dir.dir.createFile("root/a/b/c.txt", .{});
}

fn assertFs(root: *const VFile) !void {
    try testing.expect(root.children.items.len == 5);
}
