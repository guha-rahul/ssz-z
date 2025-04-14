const std = @import("std");

const isBasicType = @import("type/type_kind.zig").isBasicType;
const isBitListType = @import("type/bit_list.zig").isBitListType;
const mt = @import("persistent-merkle-tree");

pub fn Hasher(comptime ST: type) type {
    return struct {
        // pub fn hashTreeRoot(allocator: std.mem.Allocator, value: *const ST.Type, out: *[32]u8) !void {}

        pub fn init(allocator: std.mem.Allocator) !HasherData {
            switch (ST.kind) {
                .vector => {
                    const hasher_size = ((ST.chunk_count + 1) / 2) * 64;
                    if (comptime isBasicType(ST.Element)) {
                        return try HasherData.initCapacity(allocator, hasher_size, null);
                    } else {
                        var children = try allocator.alloc(HasherData, 1);
                        children[0] = try Hasher(ST.Element).init(allocator);
                        return try HasherData.initCapacity(allocator, hasher_size, children);
                    }
                },
                .container => {
                    const hasher_size = ((ST.chunk_count + 1) / 2) * 64;
                    var children = try allocator.alloc(HasherData, ST.fields.len);
                    inline for (ST.fields, 0..) |field, i| {
                        if (comptime isBasicType(field.type)) {
                            children[i] = try HasherData.initCapacity(allocator, 0, null);
                        } else {
                            children[i] = try Hasher(field.type).init(allocator);
                        }
                    }
                    return try HasherData.initCapacity(allocator, hasher_size, children);
                },
                .list => {
                    const hasher_size = ((ST.chunk_count + 1) / 2) * 64;
                    if (comptime isBasicType(ST.Element)) {
                        return try HasherData.initCapacity(allocator, hasher_size, null);
                    } else {
                        var children = try allocator.alloc(HasherData, 1);
                        children[0] = try Hasher(ST.Element).init(allocator);
                        return try HasherData.initCapacity(allocator, hasher_size, children);
                    }
                },
                else => unreachable,
            }
        }

        pub fn hash(scratch: *HasherData, value: *const ST.Type, out: *[32]u8) !void {
            if (comptime isBasicType(ST)) {
                @memset(out, 0);
                switch (ST.kind) {
                    .uint => {
                        std.mem.writeInt(ST.Type, out[0..ST.fixed_size], value.*, .little);
                    },
                    .bool => {
                        out[0] = @intFromBool(value.*);
                    },
                    else => unreachable,
                }
            } else {
                @memset(scratch.chunks.items, 0);
                switch (ST.kind) {
                    .vector, .list => {
                        if (comptime isBitListType(ST)) {
                            @memcpy(scratch.chunks.items[0..value.data.items.len], value.data.items);
                        } else if (comptime isBasicType(ST.Element)) {
                            _ = ST.serializeIntoBytes(value, scratch.chunks.items);
                        } else {
                            for (value, 0..) |element, i| {
                                try Hasher(ST.Element).hash(&scratch.children.?[0], &element, scratch.chunks.items[i * 32 ..][0..32]);
                            }
                        }
                    },
                    .container => {
                        inline for (ST.fields, 0..) |field, i| {
                            const field_value = @field(value, field.name);
                            try Hasher(field.type).hash(&scratch.children.?[i], &field_value, scratch.chunks.items[i * 32 ..][0..32]);
                        }
                    },
                    else => unreachable,
                }
                try mt.merkleizeBlocksBytes(mt.sha256Hash, scratch.chunks.items, ST.chunk_count, out);

                if (ST.kind == .list) {
                    if (ST.Element.kind == .bool) {
                        try mt.mixInLength(value.bit_len, out);
                    } else {
                        try mt.mixInLength(value.items.len, out);
                    }
                }
            }
        }
    };
}

pub const HasherData = struct {
    chunks: std.ArrayList(u8),
    children: ?[]HasherData,

    pub fn initCapacity(allocator: std.mem.Allocator, capacity: usize, children: ?[]HasherData) !HasherData {
        var chunks = try std.ArrayList(u8).initCapacity(allocator, capacity);
        chunks.expandToCapacity();
        return HasherData{
            .chunks = chunks,
            .children = children,
        };
    }

    pub fn deinit(self: HasherData, allocator: std.mem.Allocator) void {
        if (self.children) |children| {
            for (children) |child| {
                child.deinit(allocator);
            }
            allocator.free(children);
        }
        self.chunks.deinit();
    }
};
