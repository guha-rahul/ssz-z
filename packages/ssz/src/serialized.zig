const std = @import("std");
const isFixedType = @import("type/root.zig").isFixedType;

pub fn Serialized(comptime ST: type) type {
    if (comptime isFixedType(ST)) {
        return FixedSerialized(ST);
    } else {
        return VariableSerialized(ST);
    }
}

fn FixedSerialized(comptime ST: type) type {
    return struct {
        data: *[ST.fixed_size]u8,

        const Self = @This();

        pub fn init(data: *[ST.fixed_size]u8) Self {
            return Self{ .data = data };
        }

        pub fn deserialize(self: Self) ST.Type {
            var out: ST.Type = undefined;
            ST.deserializeFromBytes(self.data, &out) catch unreachable;
            return out;
        }

        pub fn getChild(self: Self, comptime path_str: []const u8) Serialized(Path(ST, path_str).Type()) {
            const P = Path(ST, path_str);
            const ChildST = P.Type();
            const offset = getOffsetFromPath(P.path);
            if (comptime isFixedType(ChildST)) {
                return Serialized(ChildST).init(self.data[offset .. offset + ChildST.fixed_size]);
            } else {
                return Serialized(ChildST).init(self.data[offset..]);
            }
        }
    };
}

fn VariableSerialized(comptime ST: type) type {
    return struct {
        data: []u8,

        const Self = @This();
        pub fn init(data: []const u8) !Self {
            try ST.validate(data);
            return Self{ .data = data };
        }

        pub fn deserialize(self: Self, allocator: std.mem.Allocator) !ST.Type {
            var out: ST.Type = undefined;
            try ST.deserializeFromBytes(self.data, allocator, &out);
            return out;
        }

        pub fn getChild(self: Self, comptime path_str: []const u8) !Serialized(PathType(ST, path_str)) {
            const P = Path(ST, path_str);
            const path = P.path;
            const ChildST = P.Type();

            var d = self.data;

            inline for (path) |item| {
                switch (item.item_type) {
                    .element => |i| {
                        switch (item.ST.kind) {
                            .vector, .list => {
                                if (item.ST.kind == .list and item.ST.Element.kind == .bool) {
                                    return error.InvalidType;
                                }
                                const length = if (item.ST.kind == .vector) item.ST.length else item.ST.deserializedLength(d);
                                if (i >= length) {
                                    return error.OutOfBounds;
                                }
                                if (comptime isFixedType(item.ST.Element)) {
                                    const element_fixed_size = item.ST.Element.fixed_size;
                                    d = d[i * element_fixed_size .. (i + 1) * element_fixed_size];
                                } else {
                                    const start = std.mem.readInt(u32, d[i * 4 ..][0..4], .little);
                                    const end = if (i == length - 1) d.len else std.mem.readInt(u32, d[(i + 1) * 4 ..][0..4], .little);
                                    d = d[start..end];
                                }
                            },
                            .container => {
                                const range = try item.ST.readFieldRanges(d)[i];
                                d = d[range[0]..range[1]];
                            },
                        }
                    },
                    .length => @compileError("'length' not supported"),
                }
            }

            if (comptime isFixedType(ChildST)) {
                return Serialized(ChildST).init(d[0..ChildST.fixed_size]);
            } else {
                return Serialized(ChildST).init(d);
            }
        }
    };
}

const PathItemType = union(enum) {
    element: usize,
    length,
};

const PathItem = struct {
    item_type: PathItemType,
    ST: type,
};

pub fn Path(comptime ST: type, comptime path_str: []const u8) type {
    return struct {
        pub const path = getPath(ST, path_str);
        pub const last_item = path[path.len - 1];

        pub fn Type() type {
            return switch (last_item.item_type) {
                .element => |i| {
                    return switch (last_item.ST.kind) {
                        .length, .vector => last_item.ST.Element,
                        .container => last_item.ST.fields[i],
                        else => @compileError("invalid"),
                    };
                },
                .length => @compileError("invalid"),
            };
        }
    };
}

pub fn PathType(comptime ST: type, comptime path_str: []const u8) type {
    return getType(getPath(ST, path_str));
}

pub fn getType(comptime path: []PathItem) type {
    const last_item = path[path.len - 1];
    return switch (last_item.item_type) {
        .element => |i| {
            return switch (last_item.ST.kind) {
                .length, .vector => last_item.ST.Element,
                .container => last_item.ST.fields[i],
                else => @compileError("invalid"),
            };
        },
        .length => @compileError("invalid"),
    };
}

pub fn getPath(comptime ST: type, comptime path_str: []const u8) [std.mem.count(u8, path_str, ".") + 1]PathItem {
    const path_len = std.mem.count(u8, path_str, ".") + 1;
    var path: [path_len]PathItem = undefined;
    var iterator = std.mem.tokenizeScalar(u8, path_str, '.');
    var T: type = ST;
    var i: usize = 0;
    while (iterator.next()) |item| {
        switch (T.kind) {
            .uint, .bool => @compileError("Invalid path"),
            .vector => {
                const element_index = std.fmt.parseInt(usize, item, 10) catch @compileError("Invalid index");
                if (element_index >= T.length) {
                    @compileError("Index past length");
                }

                path[i] = .{
                    .ST = T,
                    .item_type = .{
                        .element = element_index,
                    },
                };
                T = T.Element;
            },
            .list => {
                if (std.mem.eql(u8, item, "length")) {
                    if (i != path_len - 1) {
                        @compileError("'length' must be the end of the path");
                    }
                    path[i] = .{
                        .ST = T,
                        .item_type = .length,
                    };
                    continue;
                }

                const element_index = std.fmt.parseInt(usize, item, 10) catch @compileError("Invalid index");
                if (element_index >= T.limit) {
                    @compileError("Index past limit");
                }

                path[i] = .{
                    .ST = T,
                    .item_type = .{
                        .element = element_index,
                    },
                };
                T = T.Element;
            },
            .container => {
                const field_index = T.getFieldIndex(item);
                path[i] = .{ .ST = T, .item_type = .{
                    .element = field_index,
                } };

                T = T.fields[field_index];
            },
        }
        i += 1;
    }
    return path;
}

pub fn getOffsetFromPath(comptime path: []const PathItem) usize {
    var offset: usize = 0;
    inline for (path) |path_item| {
        switch (path_item.item_type) {
            .length => @compileError("Cannot get an offset for 'length'"),
            .element => |i| {
                switch (path_item.ST.kind) {
                    .container => {
                        offset += i.ST.field_offsets[comptime i.ST.getFieldIndex(i.field_name)];
                    },
                    .vector, .list => {
                        if (!comptime isFixedType(i.ST.Element)) {
                            @compileError("Cannot get an offset for variable-length array elements");
                        }
                        offset += i.ST.Element.fixed_size * i.element_index;
                    },
                }
            },
        }
    }
    return offset;
}

pub fn getOffset(comptime ST: type, comptime path_str: []const u8) usize {
    const path = getPath(ST, path_str);
    return getOffsetFromPath(&path);
}

const types = @import("type/root.zig");

test {
    std.testing.refAllDecls(@This());

    const Root = types.ByteVectorType(32);
    const Checkpoint = types.FixedContainerType(struct {
        slot: types.UintType(64),
        root: Root,
    });

    _ = getPath(Checkpoint, "slot");
    _ = getPath(Checkpoint, "root");
    _ = getPath(Checkpoint, "root.31");
    _ = getPath(Root, "0");
    const o1 = getOffset(Checkpoint, "root.20");

    var c_buf: [Checkpoint.fixed_size]u8 = undefined;
    const x = Serialized(Checkpoint){ .data = &c_buf };
    x.get(u64, "slot");
    x.get("root");

    std.debug.print("{d}\n", .{o1});
    std.debug.print("{d}\n", .{Checkpoint.field_offsets});
}
