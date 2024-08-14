const std = @import("std");

pub const Node = struct {
    name: []const u8,
    value: []const u8,
    attributes: std.StringHashMap([]const u8),
    childrens: std.ArrayList(*Node),
    parent: ?*Node = null,

    fn create(allocator: std.mem.Allocator, name: []const u8, value: []const u8, attributes: std.StringHashMap([]const u8)) !*Node {
        var node = try allocator.create(Node);
        node.name = name;
        node.value = value;
        node.attributes = attributes;
        node.childrens = std.ArrayList(*Node).init(allocator);
        node.parent = null;
        return node;
    }

    pub fn destroy(self: *Node, allocator: std.mem.Allocator) void {
        for (self.childrens.items) |child| {
            child.destroy(allocator);
        }
        allocator.destroy(self);
    }

    fn stringify(self: *Node, out_stream: anytype, depth: usize) !void {
        try out_stream.writeByteNTimes(' ', depth);
        try out_stream.print("{s} {{ ", .{self.name});
        var it = self.attributes.iterator();
        while (it.next()) |entry| {
            try out_stream.print("{s} = {s} | ", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
        try out_stream.print("\n", .{});
        for (self.childrens.items) |child| {
            try child.stringify(out_stream, depth + 2);
        }
        try out_stream.writeByteNTimes(' ', depth);
        try out_stream.print("}}\n", .{});
    }
};

fn readName(tag: []u8) []u8 {
    var end: usize = tag.len;
    for (tag, 0..) |char, idx| {
        if (char == ' ' or char == '/') {
            end = idx;
            break;
        }
    }
    return tag[0..end];
}

fn readAttributes(allocator: std.mem.Allocator, tag: []u8) !std.StringHashMap([]const u8) {
    var attributes = std.StringHashMap([]const u8).init(allocator);
    var it = std.mem.tokenizeScalar(u8, tag, ' ');
    while (it.next()) |word| {
        const idx = std.mem.indexOfScalarPos(u8, word, 0, '=') orelse return error.InvalidArgument;
        const endidx = std.mem.indexOfScalarPos(u8, word, idx + 2, '"') orelse return error.InvalidArgument;

        const key = word[0..idx];
        const value = word[idx + 2 .. endidx];

        try attributes.put(key, value);
    }

    return attributes;
}

// TODO: Read node value from file
pub fn loadFromPath(allocator: std.mem.Allocator, path: []const u8) !*Node {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var bufferedReader = std.io.bufferedReader(file.reader());
    const reader = bufferedReader.reader();
    var currentNode: ?*Node = null;
    while (true) {
        try reader.skipUntilDelimiterOrEof('<');
        const tag = try reader.readUntilDelimiterOrEofAlloc(allocator, '>', 4096) orelse break;
        switch (tag[0]) {
            '!', '?' => {
                // Comment or declaration
            },
            '/' => {
                // Closing node
                if (currentNode) |oldNode| {
                    if (oldNode.parent) |parent| {
                        currentNode = parent;
                    }
                }
            },
            else => {
                // New node
                const name = readName(tag);
                const attributes = try readAttributes(allocator, tag[name.len..]);

                var node = try Node.create(allocator, name, "", attributes);

                if (currentNode) |parentNode| {
                    try parentNode.childrens.append(node);
                    node.parent = parentNode;
                }
                if (tag[tag.len - 1] != '/')
                    currentNode = node;
            },
        }
    }
    if (currentNode == null) return error.NoNodeFound;

    return currentNode.?;
}
