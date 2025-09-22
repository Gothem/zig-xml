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
        node.childrens = .empty;
        node.parent = null;
        return node;
    }

    pub fn destroy(self: *Node, allocator: std.mem.Allocator) void {
        for (self.childrens.items) |child| {
            child.destroy(allocator);
        }
        var iter = self.attributes.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.attributes.deinit();
        self.childrens.deinit(allocator);
        allocator.free(self.name);
        allocator.destroy(self);
    }

    fn stringify(self: *Node, writer: *std.io.Writer, depth: usize) !void {
        _ = try writer.splatByte(' ', depth);
        try writer.print("{s} {{ ", .{self.name});
        var it = self.attributes.iterator();
        while (it.next()) |entry| {
            try writer.print("{s} = {s} | ", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
        try writer.print("\n", .{});
        for (self.childrens.items) |child| {
            try child.stringify(writer, depth + 2);
        }
        _ = try writer.splatByte(' ', depth);
        try writer.print("}}\n", .{});
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
        const endidx = std.mem.indexOfAnyPos(u8, word, idx + 2, "\"'") orelse return error.InvalidArgument;

        const key = try allocator.dupe(u8, word[0..idx]);
        const value = try allocator.dupe(u8, word[idx + 2 .. endidx]);

        try attributes.put(key, value);
    }

    return attributes;
}

// TODO: Read node value from file
pub fn loadFromPath(allocator: std.mem.Allocator, path: []const u8) !*Node {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var buffer: [4096]u8 = undefined;
    var file_reader = file.reader(&buffer);
    const reader = &file_reader.interface;

    var currentNode: ?*Node = null;
    _ = try reader.discardDelimiterInclusive('<');
    while (reader.takeDelimiterExclusive('>')) |tag| : (_ = reader.discardDelimiterInclusive('<') catch 0) {
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
                const name = try allocator.dupe(u8, readName(tag));
                const endpoint = if (tag[tag.len - 1] == '/') tag.len - 1 else tag.len;
                const attributes = try readAttributes(allocator, tag[name.len..endpoint]);

                var node = try Node.create(allocator, name, "", attributes);

                if (currentNode) |parentNode| {
                    try parentNode.childrens.append(allocator, node);
                    node.parent = parentNode;
                }
                if (tag[tag.len - 1] != '/')
                    currentNode = node;
            },
        }
    } else |err| {
        if (err != error.EndOfStream) return err;
    }
    if (currentNode == null) return error.NoNodeFound;

    return currentNode.?;
}

test "read xml" {
    const xml = try loadFromPath(std.testing.allocator, "org.kde.StatusNotifierWatcher.xml");

    var buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &stdout_writer.interface;

    try xml.stringify(stdout, 0);
    xml.destroy(std.testing.allocator);
}
