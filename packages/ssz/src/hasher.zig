const std = @import("std");

fn Hasher(comptime ST: type) type {
    return struct {
        // pub fn hashTreeRoot(allocator: std.mem.Allocator, value: *const ST.Type, out: *[32]u8) !void {}

        pub fn init(allocator: std.mem.Allocator) !HasherData {
            switch (ST.kind) {
                .vector => {
                    const hasher_size = ((ST.max_chunk_count + 1) / 2) * 64;
                    if (ST.Element.is_basic) {
                        return try HasherData.initCapacity(allocator, hasher_size, null);
                    } else {
                        var children = try allocator.alloc(HasherData, 1);
                        children[0] = try Hasher(ST.Element).init(allocator);
                        return try HasherData.initCapacity(allocator, hasher_size, children);
                    }
                },
                .container => {
                    const hasher_size = ((ST.max_chunk_count + 1) / 2) * 64;
                    var children = try allocator.alloc(HasherData, ST.fields_len);
                    inline for (ST.fields, 0..) |field, i| {
                        if (field.type.is_basic) {
                            children[i] = try HasherData.initCapacity(allocator, 0, null);
                        } else {
                            children[i] = try Hasher(field.type).init(allocator);
                        }
                    }
                    return try HasherData.initCapacity(allocator, hasher_size, children);
                },
                else => unreachable,
            }
        }

        pub fn hash(scratch: *HasherData, value: *const ST.Type, out: *[32]u8) !void {
            if (ST.is_basic) {
                @memset(out, 0);
                switch (ST.kind) {
                    .uint => {
                        const out_as_val = std.mem.bytesAsValue(ST.Type, out);
                        out_as_val.* = if (native_endian == .big) @byteSwap(value.*) else value.*;
                    },
                    .bool => {
                        out[0] = value;
                    },
                    else => unreachable,
                }
            } else {
                @memset(scratch.chunks.items, 0);
                switch (ST.kind) {
                    .vector, .list => {
                        if (ST.Element.is_basic) {
                            _ = ST.serializeIntoBytes(value, scratch.chunks.items);
                        } else {
                            for (value, 0..) |element, i| {
                                try Hasher(ST.Element).hash(scratch.children.?[0], &element, scratch.chunks.items[i * 32 .. (i + 1) * 32]);
                            }
                        }
                    },
                    .container => {
                        inline for (ST.fields, 0..) |field, i| {
                            const field_value = @field(value, field.name);
                            try Hasher(field.type).hash(&scratch.children.?[i], &field_value, scratch.chunks.items[i * 32 .. (i + 1) * 32]);
                        }
                    },
                    else => unreachable,
                }
                merkleize(scratch.chunks.items, ST.max_chunk_count, out);

                if (ST.kind == .list) {
                    mixInLength(value.len, out);
                }
            }
        }
    };
}

const HasherData = struct {
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
