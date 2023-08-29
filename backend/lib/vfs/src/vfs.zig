const std = @import("std");
const fs = std.fs;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const testing = std.testing;
const expect = testing.expect;
const eqSlice = testing.expectEqualSlices;
const eq = std.testing.expectEqual;

const Fd = struct { value: u32 };
const FdMap = std.AutoHashMap(Fd, *VFile);

fn newFd() Fd {
    const FdCounter = struct {
        var count: u32 = 0;
    };
    defer FdCounter.count += 1;

    return Fd{ .value = FdCounter.count };
}

const VFile = struct {
    const Kind = fs.File.Kind;

    fd: Fd,
    path: []const u8,
    children: ArrayList(*VFile),
    parent: ?*VFile,
    kind: Kind,

    fn init(allocator: Allocator, path: []const u8, kind: Kind) !VFile {
        return VFile{
            .fd = newFd(),
            .path = path,
            .children = ArrayList(*VFile).init(allocator),
            .parent = null,
            .kind = kind,
        };
    }

    fn addChild(self: *VFile, node: *VFile) !void {
        node.parent = self;
        try self.children.append(node);
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

pub const Node = struct {
    fd: Fd,
    kind: VFile.Kind,
    path: []const u8,

    fn fromVFile(vf: *const VFile) Node {
        return .{ .fd = vf.fd, .path = vf.path, .kind = vf.kind };
    }
};

pub const VfsError = error{NodeNotFound};

pub const Vfs = struct {
    const Self = @This();

    fd_map: FdMap,
    arena: ArenaAllocator,
    root: *VFile,

    pub fn init(allocator: Allocator, path: []const u8) !Self {
        var arena = ArenaAllocator.init(allocator);
        const arenaAlloc = arena.allocator();

        var fd_map = FdMap.init(arenaAlloc);

        var d = try fs.openDirAbsolute(path, .{ .access_sub_paths = true, .no_follow = true });
        defer d.close();
        const id = fs.IterableDir{ .dir = d };
        var fs_walker = try id.walk(arenaAlloc);
        defer fs_walker.deinit();

        const root_path = try std.fmt.allocPrint(arenaAlloc, "{s}", .{std.fs.path.basename(path)});
        var root = try arenaAlloc.create(VFile);
        root.* = try VFile.init(arenaAlloc, root_path, VFile.Kind.directory);
        try fd_map.put(root.fd, root);

        try walkDirs(arenaAlloc, &fd_map, &fs_walker, root);

        return Self{
            .arena = arena,
            .root = root,
            .fd_map = fd_map,
        };
    }
    pub fn deinit(self: Self) void {
        self.arena.deinit();
    }
    pub fn print(self: Self, string: *ArrayList(u8)) !void {
        return self.root.print(string);
    }
    fn walkDirs(allocator: Allocator, fd_map: *FdMap, fs_walker: *fs.IterableDir.Walker, root: *VFile) !void {
        var stack = try ArrayList(*VFile).initCapacity(allocator, 32); // stack max len is equal to fs' max depth
        defer stack.deinit();

        try stack.append(root);

        while (try fs_walker.next()) |next| {
            var node = try allocator.create(VFile);
            const path = try std.fmt.allocPrint(allocator, "{s}", .{next.path});
            node.* = try VFile.init(allocator, path, next.kind);
            try fd_map.put(node.fd, node);

            const node_parent = fs.path.dirname(node.path) orelse root.path;

            var top = stack.pop();
            while (!std.mem.eql(u8, top.path, node_parent)) {
                top = stack.pop();
            }
            try stack.append(top);
            try stack.append(node);
            try top.addChild(node);
        }
    }
    pub fn rootNode(self: Self) Node {
        return Node.fromVFile(self.root);
    }
    pub fn children(self: Self, allocator: Allocator, parent: Node) (Allocator.Error || VfsError)![]Node {
        if (self.fd_map.get(parent.fd)) |p| {
            const len = p.children.items.len;

            var nodes = try allocator.alloc(Node, len);
            for (p.children.items, 0..len) |child, i| {
                nodes[i] = Node.fromVFile(child);
            }

            return nodes;
        } else {
            return VfsError.NodeNotFound;
        }
    }

    pub const Iterator = struct {
        vfs: *const Self,
        fd_values_it: FdMap.ValueIterator,
        pub fn next(it: *Iterator) ?Node {
            const v = it.fd_values_it.next();
            return if (v) |vf| Node.fromVFile(vf.*) else null;
        }
    };
    /// Unordered iterator. Use this one if you need to visit all nodes otherwise, use `walker`
    pub fn iterator(self: *const Self) Iterator {
        return Iterator{ .vfs = self, .fd_values_it = self.fd_map.valueIterator() };
    }
    pub const Walker = struct {
        allocator: Allocator,
        vfs: *const Self,
        stack: ArrayList(*VFile),
        pub fn deinit(w: Walker) void {
            w.stack.deinit();
        }

        pub fn next(w: *Walker) !?Node {
            if (w.stack.popOrNull()) |top| {
                const node = Node.fromVFile(top);
                try w.stack.appendSlice(top.children.items);
                return node;
            } else return null;
        }
    };
    pub fn walker(self: *const Self, allocator: Allocator) !Walker {
        var stack = ArrayList(*VFile).init(allocator);
        try stack.append(self.root);
        return Walker{
            .vfs = self,
            .allocator = allocator,
            .stack = stack,
        };
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

    var string = try ArrayList(u8).initCapacity(a, 4096);
    defer string.deinit();
    try string.append('\n');
    try vfs.root.print(&string);

    {
        try eqSlice(u8, "root", vfs.rootNode().path);

        const root_nodes = try vfs.children(a, vfs.rootNode());
        defer a.free(root_nodes);
        try expect(root_nodes.len == 5);
    }
}

test "Vfs iterator" {
    const a = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    try makeTestData(tmp_dir);

    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    var d = try tmp_dir.dir.realpath("root", &buf);

    const vfs = try Vfs.init(a, d);
    defer vfs.deinit();

    {
        var it = vfs.iterator();
        var count: usize = 0;
        while (it.next() != null) : (count += 1) {}
        try expect(test_dir_total_nodes == count);
    }
    {
        var walker = try vfs.walker(a);
        defer walker.deinit();

        const root = (try walker.next()).?;
        try eqSlice(u8, "root", root.path);

        var count: usize = 1;
        while (try walker.next() != null) : (count += 1) {}
        try expect(test_dir_total_nodes == count);
    }
}
const test_dir_total_nodes = 12;
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
