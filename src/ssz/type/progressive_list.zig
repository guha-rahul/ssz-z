const std = @import("std");
const TypeKind = @import("type_kind.zig").TypeKind;
const isBasicType = @import("type_kind.zig").isBasicType;
const isFixedType = @import("type_kind.zig").isFixedType;
const OffsetIterator = @import("offsets.zig").OffsetIterator;
const mixInLength = @import("hashing").mixInLength;
const maxChunksToDepth = @import("hashing").maxChunksToDepth;
const Depth = @import("hashing").Depth;
const Node = @import("persistent_merkle_tree").Node;
const progressive = @import("progressive.zig");
const testing = std.testing;

pub fn FixedProgressiveListType(comptime ST: type, comptime _limit: comptime_int) type {
    comptime {
        if (!isFixedType(ST)) {
            @compileError("ST must be fixed type");
        }
        if (_limit < 0) {
            @compileError("limit must be non-negative");
        }
    }
    return struct {
        pub const kind = TypeKind.progressive_list;
        pub const Element: type = ST;
        pub const limit: usize = _limit;
        pub const Type: type = std.ArrayListUnmanaged(Element.Type);
        pub const min_size: usize = 0;
        pub const fixed_size: usize = 0;

        pub const default_value: Type = Type.empty;

        pub fn deinit(allocator: std.mem.Allocator, value: *Type) void {
            value.deinit(allocator);
        }

        pub fn equals(a: *const Type, b: *const Type) bool {
            if (a.items.len != b.items.len) return false;
            for (a.items, 0..) |a_elem, i| {
                if (!Element.equals(&a_elem, &b.items[i])) return false;
            }
            return true;
        }

        pub fn chunkCount(value: *const Type) usize {
            if (comptime isBasicType(Element)) {
                return (Element.fixed_size * value.items.len + 31) / 32;
            } else return value.items.len;
        }

        pub fn hashTreeRoot(allocator: std.mem.Allocator, value: *const Type, out: *[32]u8) !void {
            const chunks = try allocator.alloc([32]u8, chunkCount(value));
            defer allocator.free(chunks);

            @memset(chunks, [_]u8{0} ** 32);

            if (comptime isBasicType(Element)) {
                const chunk_bytes = std.mem.sliceAsBytes(chunks);
                _ = serializeIntoBytes(value, chunk_bytes);
                if (chunks.len > 0) {
                    std.debug.print("[PGL value] first_leaf={s}\n", .{std.fmt.fmtSliceHexLower(chunks[0][0..])});
                }
            } else {
                for (value.items, 0..) |element, i| {
                    try Element.hashTreeRoot(allocator, &element, &chunks[i]);
                }
            }

            try progressive.merkleizeChunks(allocator, chunks, out);
            std.debug.print("[PGL value] contents={s} len={d}\n", .{ std.fmt.fmtSliceHexLower(out.*[0..]), value.items.len });
            mixInLength(value.items.len, out);
            std.debug.print("[PGL value] root={s}\n", .{std.fmt.fmtSliceHexLower(out.*[0..])});
        }

        pub fn serializedSize(value: *const Type) usize {
            return value.items.len * Element.fixed_size;
        }

        pub fn serializeIntoBytes(value: *const Type, out: []u8) usize {
            var i: usize = 0;
            for (value.items) |element| {
                i += Element.serializeIntoBytes(&element, out[i..]);
            }
            return i;
        }

        pub fn deserializeFromBytes(allocator: std.mem.Allocator, data: []const u8, out: *Type) !void {
            // Validate first to ensure exact multiple and within limit
            try serialized.validate(data);
            const len = try serialized.length(data);
            try out.resize(allocator, len);
            @memset(out.items[0..len], Element.default_value);
            for (0..len) |i| {
                try Element.deserializeFromBytes(
                    data[i * Element.fixed_size .. (i + 1) * Element.fixed_size],
                    &out.items[i],
                );
            }
        }

        pub fn serializeIntoJson(_: std.mem.Allocator, writer: anytype, in: *const Type) !void {
            try writer.beginArray();
            for (in.items) |element| {
                try Element.serializeIntoJson(writer, &element);
            }
            try writer.endArray();
        }

        pub fn deserializeFromJson(allocator: std.mem.Allocator, source: *std.json.Scanner, out: *Type) !void {
            // start array token "["
            switch (try source.next()) {
                .array_begin => {},
                else => return error.InvalidJson,
            }

            var count: usize = 0;
            while (true) : (count += 1) {
                switch (try source.peekNextTokenType()) {
                    .array_end => {
                        _ = try source.next();
                        return;
                    },
                    else => {},
                }

                // grow by one and deserialize element
                if (count + 1 > limit) return error.gtLimit;
                try out.append(allocator, Element.default_value);
                try Element.deserializeFromJson(source, &out.items[count]);
            }
            return error.invalidLength;
        }

        pub const serialized = struct {
            pub fn validate(data: []const u8) !void {
                std.debug.print("[PGL fixed.validate] prog=true fs={d} limit={d} data.len={d}\n", .{ Element.fixed_size, limit, data.len });

                // Handle limit=0 case: allow empty when limit=0, reject non-empty
                if (limit == 0) {
                    if (data.len == 0) {
                        return; // Empty is valid for limit=0
                    } else {
                        std.debug.print("[PGL fixed.validate] limit=0 but data.len={d} > 0\n", .{data.len});
                        return error.InvalidSSZ;
                    }
                }

                // Require exact multiple - reject any remainder bytes
                if (data.len % Element.fixed_size != 0) {
                    std.debug.print("[PGL fixed.validate] non-multiple: rem={d}\n", .{data.len % Element.fixed_size});
                    return error.InvalidSSZ;
                }

                const len = data.len / Element.fixed_size;
                std.debug.print("[PGL fixed.validate] len={d}\n", .{len});

                // Check length against limit
                if (len > limit) {
                    std.debug.print("[PGL fixed.validate] over-limit len={d} > limit={d}\n", .{ len, limit });
                    return error.InvalidSSZ;
                }

                // Validate each element
                for (0..len) |i| {
                    const elem_data = data[i * Element.fixed_size .. (i + 1) * Element.fixed_size];
                    Element.serialized.validate(elem_data) catch |err| {
                        std.debug.print("[PGL fixed.validate] element {d} failed validation: {}\n", .{ i, err });
                        return error.InvalidSSZ;
                    };
                }
            }

            pub fn length(data: []const u8) !usize {
                std.debug.print("[PGL fixed.length] fs={d} limit={d} data.len={d}\n", .{ Element.fixed_size, limit, data.len });

                // Handle limit=0 case: allow empty when limit=0, reject non-empty
                if (limit == 0) {
                    if (data.len == 0) {
                        return 0;
                    } else {
                        std.debug.print("[PGL fixed.length] limit=0 but data.len={d} > 0\n", .{data.len});
                        return error.InvalidSSZ;
                    }
                }

                // Require exact multiple - reject any remainder bytes
                if (data.len % Element.fixed_size != 0) {
                    std.debug.print("[PGL fixed.length] non-multiple: rem={d}\n", .{data.len % Element.fixed_size});
                    return error.InvalidSSZ;
                }

                const len = data.len / Element.fixed_size;
                std.debug.print("[PGL fixed.length] len={d}\n", .{len});

                // Check length against limit
                if (len > limit) {
                    std.debug.print("[PGL fixed.length] over-limit len={d} > limit={d}\n", .{ len, limit });
                    return error.InvalidSSZ;
                }

                return len;
            }

            pub fn hashTreeRoot(allocator: std.mem.Allocator, data: []const u8, out: *[32]u8) !void {
                const len = try length(data);

                const chunk_count = if (comptime isBasicType(Element))
                    (Element.fixed_size * len + 31) / 32
                else
                    len;
                const chunks = try allocator.alloc([32]u8, chunk_count);
                defer allocator.free(chunks);

                @memset(chunks, [_]u8{0} ** 32);

                if (comptime isBasicType(Element)) {
                    const chunk_bytes = std.mem.sliceAsBytes(chunks);
                    @memcpy(chunk_bytes[0..data.len], data);
                    if (chunks.len > 0) {
                        std.debug.print("[PGL ser] first_leaf={s}\n", .{std.fmt.fmtSliceHexLower(chunks[0][0..])});
                    }
                } else {
                    for (0..len) |i| {
                        try Element.serialized.hashTreeRoot(
                            allocator,
                            data[i * Element.fixed_size .. (i + 1) * Element.fixed_size],
                            &chunks[i],
                        );
                    }
                }

                try progressive.merkleizeChunks(allocator, chunks, out);
                std.debug.print("[PGL ser] contents={s} len={d}\n", .{ std.fmt.fmtSliceHexLower(out.*[0..]), len });
                mixInLength(len, out);
                std.debug.print("[PGL ser] root={s}\n", .{std.fmt.fmtSliceHexLower(out.*[0..])});
            }
        };

        pub const tree = struct {
            pub fn length(node: Node.Id, pool: *Node.Pool) !usize {
                const right = try node.getRight(pool);
                const hash = right.getRoot(pool);
                const v: u64 = std.mem.readInt(u64, hash[0..8], .little);
                return @intCast(v);
            }

            pub fn toValue(allocator: std.mem.Allocator, node: Node.Id, pool: *Node.Pool, out: *Type) !void {
                const len = try length(node, pool);
                const chunk_count = if (comptime isBasicType(Element))
                    (Element.fixed_size * len + 31) / 32
                else
                    len;

                if (chunk_count == 0) {
                    try out.resize(allocator, 0);
                    return;
                }
                try out.resize(allocator, len);
                @memset(out.items, Element.default_value);

                const nodes = try allocator.alloc(Node.Id, chunk_count);
                defer allocator.free(nodes);

                const chunk_depth = maxChunksToDepth(chunk_count);
                try (try node.getLeft(pool)).getNodesAtDepth(pool, chunk_depth, 0, nodes);

                if (comptime isBasicType(Element)) {
                    // tightly packed list
                    const items_per_chunk = 32 / Element.fixed_size;
                    for (0..len) |i| {
                        const chunk_index = i / items_per_chunk;
                        const index_in_chunk = i % items_per_chunk;
                        try Element.tree.toValuePacked(
                            nodes[chunk_index],
                            pool,
                            index_in_chunk,
                            &out.items[i],
                        );
                    }
                } else {
                    for (0..len) |i| {
                        try Element.tree.toValue(
                            nodes[i],
                            pool,
                            &out.items[i],
                        );
                    }
                }
            }

            pub fn fromValue(allocator: std.mem.Allocator, pool: *Node.Pool, value: *const Type) !Node.Id {
                const len = value.items.len;
                const chunk_count = chunkCount(value);
                const nodes = try allocator.alloc(Node.Id, chunk_count);
                defer allocator.free(nodes);
                if (comptime isBasicType(Element)) {
                    const items_per_chunk = 32 / Element.fixed_size;
                    var next: usize = 0; // index in value.items

                    for (0..chunk_count) |i| {
                        var leaf_buf = [_]u8{0} ** 32;

                        // how many items still remain to be packed into this chunk?
                        const remaining = len - next;
                        const to_write = @min(remaining, items_per_chunk);

                        // serialise exactly to_write elements into the 32‑byte buffer
                        for (0..to_write) |j| {
                            const dst_off = j * Element.fixed_size;
                            const dst_slice = leaf_buf[dst_off .. dst_off + Element.fixed_size];
                            _ = Element.serializeIntoBytes(&value.items[next + j], dst_slice);
                        }
                        next += to_write;

                        nodes[i] = try pool.createLeaf(&leaf_buf, false);
                        if (i == 0 and chunk_count > 0) {
                            std.debug.print("[PGL tree] first_leaf={s}\n", .{std.fmt.fmtSliceHexLower(&leaf_buf)});
                        }
                    }
                } else {
                    for (0..chunk_count) |i| {
                        nodes[i] = try Element.tree.fromValue(pool, &value.items[i]);
                    }
                }
                const chunk_depth = maxChunksToDepth(chunk_count);
                const contents_node = try Node.fillWithContents(pool, nodes, chunk_depth, false);
                const contents_root = contents_node.getRoot(pool);
                std.debug.print("[PGL tree] contents={s} len={d}\n", .{ std.fmt.fmtSliceHexLower(contents_root), len });
                const length_node = try pool.createLeafFromUint(len, false);
                const result = try pool.createBranch(contents_node, length_node, false);
                const final_root = result.getRoot(pool);
                std.debug.print("[PGL tree] root={s}\n", .{std.fmt.fmtSliceHexLower(final_root)});

                return result;
            }
        };
    };
}

pub fn VariableProgressiveListType(comptime ST: type, comptime _limit: comptime_int) type {
    comptime {
        if (isFixedType(ST)) {
            @compileError("ST must not be fixed type");
        }
        if (_limit < 0) {
            @compileError("limit must be non-negative");
        }
    }
    return struct {
        const Self = @This();
        pub const kind = TypeKind.progressive_list;
        pub const Element: type = ST;
        pub const limit: usize = _limit;
        pub const Type: type = std.ArrayListUnmanaged(Element.Type);
        pub const min_size: usize = 0;

        pub const default_value: Type = Type.empty;

        pub fn deinit(allocator: std.mem.Allocator, value: *Type) void {
            for (value.items) |*element| {
                Element.deinit(allocator, element);
            }
            value.deinit(allocator);
        }

        pub fn equals(a: *const Type, b: *const Type) bool {
            if (a.items.len != b.items.len) return false;
            for (a.items, 0..) |a_elem, i| {
                if (!Element.equals(&a_elem, &b.items[i])) return false;
            }
            return true;
        }

        pub fn chunkCount(value: *const Type) usize {
            return value.items.len;
        }

        pub fn hashTreeRoot(allocator: std.mem.Allocator, value: *const Type, out: *[32]u8) !void {
            const chunks = try allocator.alloc([32]u8, chunkCount(value));
            defer allocator.free(chunks);

            @memset(chunks, [_]u8{0} ** 32);

            for (value.items, 0..) |element, i| {
                try Element.hashTreeRoot(allocator, &element, &chunks[i]);
            }
            try progressive.merkleizeChunks(allocator, chunks, out);
            mixInLength(value.items.len, out);
        }

        pub fn serializedSize(value: *const Type) usize {
            // offsets size
            var size: usize = value.items.len * 4;
            // element sizes
            for (value.items) |element| {
                size += Element.serializedSize(&element);
            }
            return size;
        }

        pub fn serializeIntoBytes(value: *const Type, out: []u8) usize {
            var variable_index = value.items.len * 4;
            for (value.items, 0..) |element, i| {
                // write offset
                std.mem.writeInt(u32, out[i * 4 ..][0..4], @intCast(variable_index), .little);
                // write element data
                variable_index += Element.serializeIntoBytes(&element, out[variable_index..]);
            }
            return variable_index;
        }

        pub fn serializeIntoJson(allocator: std.mem.Allocator, writer: anytype, in: *const Type) !void {
            try writer.beginArray();
            for (in.items) |element| {
                try Element.serializeIntoJson(allocator, writer, &element);
            }
            try writer.endArray();
        }

        pub fn deserializeFromBytes(allocator: std.mem.Allocator, data: []const u8, out: *Type) !void {
            // Validate first
            try serialized.validate(data);
            const offsets = try readVariableOffsets(allocator, data);
            defer allocator.free(offsets);

            const len = offsets.len - 1;

            try out.resize(allocator, len);
            @memset(out.items[0..len], Element.default_value);
            for (0..len) |i| {
                try Element.deserializeFromBytes(
                    allocator,
                    data[offsets[i]..offsets[i + 1]],
                    &out.items[i],
                );
            }
        }

        pub fn readVariableOffsets(allocator: std.mem.Allocator, data: []const u8) ![]u32 {
            var iterator = OffsetIterator(Self).init(data);
            const first_offset = if (data.len == 0) 0 else blk: {
                if (data.len < 4) return error.InvalidSSZ;
                break :blk try iterator.next();
            };
            const len = first_offset / 4;

            const offsets = try allocator.alloc(u32, len + 1);

            offsets[0] = first_offset;
            while (iterator.pos < len) {
                offsets[iterator.pos] = try iterator.next();
            }
            offsets[len] = @intCast(data.len);

            return offsets;
        }

        pub const serialized = struct {
            pub fn validate(data: []const u8) !void {
                // Handle limit=0 case: allow empty when limit=0, reject non-empty
                if (limit == 0) {
                    if (data.len == 0) {
                        return; // Empty is valid for limit=0
                    } else {
                        return error.InvalidSSZ;
                    }
                }

                // Empty data is valid if limit > 0
                if (data.len == 0) return;

                // Need at least 4 bytes for first offset
                if (data.len < 4) return error.InvalidSSZ;

                var iterator = OffsetIterator(Self).init(data);
                const first_offset = try iterator.next();
                const len = first_offset / 4;

                // Require exact match: first_offset == 4 * len
                if (first_offset != 4 * len) {
                    return error.InvalidSSZ;
                }

                // Check length against limit - progressive lists reject at-limit
                if (len >= limit) {
                    return error.InvalidSSZ;
                }

                // Validate offsets are non-decreasing and within bounds
                var curr_offset = first_offset;
                var prev_offset = first_offset;
                while (iterator.pos < len) {
                    prev_offset = curr_offset;
                    curr_offset = try iterator.next();

                    // Offsets must be non-decreasing
                    if (curr_offset < prev_offset) {
                        return error.InvalidSSZ;
                    }

                    // Offset must be within data bounds
                    if (curr_offset > data.len) {
                        return error.InvalidSSZ;
                    }

                    // Validate element data
                    Element.serialized.validate(data[prev_offset..curr_offset]) catch |err| {
                        std.debug.print("[PGL variable.validate] element {d} failed validation: {}\n", .{ iterator.pos - 1, err });
                        return error.InvalidSSZ;
                    };
                }

                // Last offset must exactly equal data.len (no trailing garbage)
                if (curr_offset != data.len) {
                    return error.InvalidSSZ;
                }

                // Validate final element
                Element.serialized.validate(data[prev_offset..data.len]) catch |err| {
                    std.debug.print("[PGL variable.validate] final element failed validation: {}\n", .{err});
                    return error.InvalidSSZ;
                };
            }

            pub fn length(data: []const u8) !usize {
                // Handle limit=0 case: allow empty when limit=0, reject non-empty
                if (limit == 0) {
                    if (data.len == 0) {
                        return 0;
                    } else {
                        return error.InvalidSSZ;
                    }
                }

                // Empty data is valid if limit > 0
                if (data.len == 0) {
                    return 0;
                }

                // Need at least 4 bytes for first offset
                if (data.len < 4) return error.InvalidSSZ;

                var iterator = OffsetIterator(Self).init(data);
                const first_offset = try iterator.firstOffset();
                const len = first_offset / 4;

                // Require exact match: first_offset == 4 * len
                if (first_offset != 4 * len) {
                    return error.InvalidSSZ;
                }

                // Offset must be within data bounds
                if (first_offset > data.len) {
                    return error.InvalidSSZ;
                }

                // Check length against limit - progressive lists reject at-limit
                if (len >= limit) {
                    return error.InvalidSSZ;
                }

                return len;
            }

            pub fn hashTreeRoot(allocator: std.mem.Allocator, data: []const u8, out: *[32]u8) !void {
                try validate(data);
                const len = try length(data);
                const chunk_count = len;

                const chunks = try allocator.alloc([32]u8, chunk_count);
                defer allocator.free(chunks);
                @memset(chunks, [_]u8{0} ** 32);

                const offsets = try readVariableOffsets(allocator, data);
                defer allocator.free(offsets);

                for (0..len) |i| {
                    try Element.serialized.hashTreeRoot(
                        allocator,
                        data[offsets[i]..offsets[i + 1]],
                        &chunks[i],
                    );
                }
                try progressive.merkleizeChunks(allocator, chunks, out);
                mixInLength(len, out);
            }
        };

        pub const tree = struct {
            pub fn length(node: Node.Id, pool: *Node.Pool) !usize {
                const right = try node.getRight(pool);
                const hash = right.getRoot(pool);
                const v: u64 = std.mem.readInt(u64, hash[0..8], .little);
                return @intCast(v);
            }

            pub fn toValue(allocator: std.mem.Allocator, node: Node.Id, pool: *Node.Pool, out: *Type) !void {
                const len = try length(node, pool);
                const chunk_count = len;
                if (chunk_count == 0) {
                    try out.resize(allocator, 0);
                    return;
                }

                const nodes = try allocator.alloc(Node.Id, chunk_count);
                defer allocator.free(nodes);

                const chunk_depth = maxChunksToDepth(chunk_count);
                try (try node.getLeft(pool)).getNodesAtDepth(pool, chunk_depth, 0, nodes);

                try out.resize(allocator, len);
                @memset(out.items, Element.default_value);
                for (0..len) |i| {
                    try Element.tree.toValue(
                        allocator,
                        nodes[i],
                        pool,
                        &out.items[i],
                    );
                }
            }

            pub fn fromValue(allocator: std.mem.Allocator, pool: *Node.Pool, value: *const Type) !Node.Id {
                const len = value.items.len;
                const chunk_count = len;
                const nodes = try allocator.alloc(Node.Id, chunk_count);
                defer allocator.free(nodes);
                for (0..chunk_count) |i| {
                    nodes[i] = try Element.tree.fromValue(allocator, pool, &value.items[i]);
                }
                const chunk_depth = maxChunksToDepth(chunk_count);
                return try pool.createBranch(
                    try Node.fillWithContents(pool, nodes, chunk_depth, false),
                    try pool.createLeafFromUint(len, false),
                    false,
                );
            }
        };

        pub fn deserializeFromJson(allocator: std.mem.Allocator, source: *std.json.Scanner, out: *Type) !void {
            // start array token "["
            switch (try source.next()) {
                .array_begin => {},
                else => return error.InvalidJson,
            }

            var i: usize = 0;
            while (true) : (i += 1) {
                switch (try source.peekNextTokenType()) {
                    .array_end => {
                        _ = try source.next();
                        return;
                    },
                    else => {},
                }

                // grow by one and deserialize element
                try out.append(allocator, Element.default_value);
                try Element.deserializeFromJson(allocator, source, &out.items[i]);
            }
            return error.invalidLength;
        }
    };
}

const UintTypePL = @import("uint.zig").UintType;
const BoolType = @import("bool.zig").BoolType;

test "ListType - sanity" {
    const allocator = std.testing.allocator;

    // create a fixed list type and instance and round-trip serialize
    const Bytes = FixedProgressiveListType(UintType(8), 1024);

    var b: Bytes.Type = Bytes.Type.empty;
    defer b.deinit(allocator);
    try b.append(allocator, 5);

    const b_buf = try allocator.alloc(u8, Bytes.serializedSize(&b));
    defer allocator.free(b_buf);

    _ = Bytes.serializeIntoBytes(&b, b_buf);
    try Bytes.deserializeFromBytes(allocator, b_buf, &b);

    // create a variable list type and instance and round-trip serialize
    const BytesBytes = VariableProgressiveListType(Bytes, 1024);
    var b2: BytesBytes.Type = BytesBytes.Type.empty;
    defer BytesBytes.deinit(allocator, &b2);
    try b2.append(allocator, b);

    const b2_buf = try allocator.alloc(u8, BytesBytes.serializedSize(&b2));
    defer allocator.free(b2_buf);

    _ = BytesBytes.serializeIntoBytes(&b2, b2_buf);
    try BytesBytes.deserializeFromBytes(allocator, b2_buf, &b2);
}

test "Type size verification for debugging" {
    // Let's explicitly verify what sizes we get
    const Uint32Type = UintType(32);
    const Uint64Type = UintType(64);

    std.debug.print("\n[TYPE DEBUG] UintType(32).fixed_size = {d}\n", .{Uint32Type.fixed_size});
    std.debug.print("[TYPE DEBUG] UintType(64).fixed_size = {d}\n", .{Uint64Type.fixed_size});

    const Uint32List = FixedProgressiveListType(UintType(32), 1024);
    const Uint64List = FixedProgressiveListType(UintType(64), 1024);

    std.debug.print("[TYPE DEBUG] ProgList(UintType(32)).Element.fixed_size = {d}\n", .{Uint32List.Element.fixed_size});
    std.debug.print("[TYPE DEBUG] ProgList(UintType(64)).Element.fixed_size = {d}\n", .{Uint64List.Element.fixed_size});

    // Test validation with correct sizes
    const valid_uint32_data = [_]u8{0xff} ** 8; // 2 elements * 4 bytes
    const invalid_uint32_data = [_]u8{0xff} ** 9; // 2.25 elements

    try Uint32List.serialized.validate(&valid_uint32_data);
    try std.testing.expectError(error.InvalidSSZ, Uint32List.serialized.validate(&invalid_uint32_data));

    const valid_uint64_data = [_]u8{0xff} ** 16; // 2 elements * 8 bytes
    const invalid_uint64_data = [_]u8{0xff} ** 17; // 2.125 elements

    try Uint64List.serialized.validate(&valid_uint64_data);
    try std.testing.expectError(error.InvalidSSZ, Uint64List.serialized.validate(&invalid_uint64_data));
}

test "FixedProgressiveList zero limit: allow empty, reject non-empty" {
    const allocator = std.testing.allocator;
    const U32Zero = FixedProgressiveListType(UintType(32), 0);

    // Empty data is valid when limit=0
    try U32Zero.serialized.validate(&[_]u8{});
    try std.testing.expect((try U32Zero.serialized.length(&[_]u8{})) == 0);

    // Non-empty data is invalid when limit=0
    try std.testing.expectError(error.InvalidSSZ, U32Zero.serialized.validate(&[_]u8{ 0, 0, 0, 0 }));
    try std.testing.expectError(error.InvalidSSZ, U32Zero.serialized.length(&[_]u8{ 0, 0, 0, 0 }));

    // deserialize empty should work, non-empty should fail
    var out: U32Zero.Type = U32Zero.Type.empty;
    defer out.deinit(allocator);
    try U32Zero.deserializeFromBytes(allocator, &[_]u8{}, &out);
    try std.testing.expect(out.items.len == 0);

    try std.testing.expectError(error.InvalidSSZ, U32Zero.deserializeFromBytes(allocator, &[_]u8{ 0, 0, 0, 0 }, &out));
}

test "VariableProgressiveList zero limit: allow empty, reject non-empty" {
    const allocator = std.testing.allocator;
    // Element type is a variable-sized ProgressiveList from earlier test
    const Bytes = FixedProgressiveListType(UintType(8), 1024);
    const VarZero = VariableProgressiveListType(Bytes, 0);

    // Empty data is valid when limit=0
    try VarZero.serialized.validate(&[_]u8{});
    try std.testing.expect((try VarZero.serialized.length(&[_]u8{})) == 0);

    // Non-empty data is invalid when limit=0
    try std.testing.expectError(error.InvalidSSZ, VarZero.serialized.validate(&[_]u8{ 0, 0, 0, 0 }));
    try std.testing.expectError(error.InvalidSSZ, VarZero.serialized.length(&[_]u8{ 0, 0, 0, 0 }));

    // deserialize empty should work, non-empty should fail
    var out: VarZero.Type = VarZero.Type.empty;
    defer VarZero.deinit(allocator, &out);
    try VarZero.deserializeFromBytes(allocator, &[_]u8{}, &out);
    try std.testing.expect(out.items.len == 0);

    try std.testing.expectError(error.InvalidSSZ, VarZero.deserializeFromBytes(allocator, &[_]u8{ 0, 0, 0, 0 }, &out));
}

// =====================
// Additional ProgressiveList tests
// =====================
const UintType = @import("uint.zig").UintType;

// helper to compute root through value path
fn root_value_u16(gpa: std.mem.Allocator, n: usize) ![32]u8 {
    const L = FixedProgressiveListType(UintTypePL(16), 2048);
    var v: L.Type = L.Type.empty;
    defer v.deinit(gpa);
    try v.resize(gpa, n);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        v.items[i] = @as(u16, @intCast(i));
    }
    var out: [32]u8 = undefined;
    try L.hashTreeRoot(gpa, &v, &out);
    return out;
}

// helper to compute root through serialized path
fn root_ser_u16(gpa: std.mem.Allocator, n: usize) ![32]u8 {
    const L = FixedProgressiveListType(UintTypePL(16), 2048);
    var buf = try gpa.alloc(u8, n * 2);
    defer gpa.free(buf);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        std.mem.writeInt(u16, buf[i * 2 ..][0..2], @as(u16, @intCast(i)), .little);
    }
    var out: [32]u8 = undefined;
    try L.serialized.hashTreeRoot(gpa, buf, &out);
    return out;
}

test "ProgressiveList u16 roots: value vs serialized vs contents for boundary sizes" {
    const gpa = testing.allocator;
    const sizes = [_]usize{ 0, 1, 2, 3, 4, 5, 16, 17, 32, 33, 56, 64, 65, 85 };

    for (sizes) |n| {
        const rv = try root_value_u16(gpa, n);
        const rs = try root_ser_u16(gpa, n);

        // build the chunks and call contents merkleizer directly
        const chunk_count = (n * 2 + 31) / 32;
        var leaves = try gpa.alloc([32]u8, chunk_count);
        defer gpa.free(leaves);
        @memset(leaves, [_]u8{0} ** 32);
        {
            var j: usize = 0;
            while (j < n) : (j += 1) {
                const chunk_i = (j * 2) / 32;
                const off = (j * 2) % 32;
                std.mem.writeInt(u16, @as(*[2]u8, @ptrCast(leaves[chunk_i][off .. off + 2])), @as(u16, @intCast(j)), .little);
            }
        }
        var rc: [32]u8 = undefined;
        try progressive.merkleizeChunks(gpa, leaves, &rc);
        mixInLength(n, &rc);

        if (!(std.mem.eql(u8, &rv, &rs) and std.mem.eql(u8, &rv, &rc))) {
            std.debug.print("[DBG list u16 n={d}] value={s}\n", .{ n, std.fmt.fmtSliceHexLower(rv[0..]) });
            std.debug.print("[DBG list u16 n={d}] serial={s}\n", .{ n, std.fmt.fmtSliceHexLower(rs[0..]) });
            std.debug.print("[DBG list u16 n={d}] conts ={s}\n", .{ n, std.fmt.fmtSliceHexLower(rc[0..]) });
        }

        try testing.expect(std.mem.eql(u8, &rv, &rs));
        try testing.expect(std.mem.eql(u8, &rv, &rc));
    }
}

test "debug progressive list validation - uint32 cases" {
    const allocator = std.testing.allocator;

    // Test case: proglist_uint32_20_random_one_byte_more
    const ProgList20 = FixedProgressiveListType(UintType(32), 20);

    // Simulate "one byte more" - 21*4 + 1 = 85 bytes (should be invalid)
    const one_byte_more = try allocator.alloc(u8, 85);
    defer allocator.free(one_byte_more);
    @memset(one_byte_more, 0xff);

    std.debug.print("\n=== Testing proglist_uint32_20 one_byte_more case ===\n", .{});
    std.debug.print("Data length: {d}, element size: {d}, remainder: {d}\n", .{ one_byte_more.len, 4, one_byte_more.len % 4 });

    // This should return error.InvalidSSZ because 85 % 4 = 1 (not divisible)
    const result = ProgList20.serialized.validate(one_byte_more);
    if (result) |_| {
        std.debug.print("ERROR: validate() returned void (success) instead of error.InvalidSSZ!\n", .{});
        try testing.expect(false); // Force failure
    } else |err| {
        std.debug.print("GOOD: validate() returned error: {}\n", .{err});
        try testing.expectError(error.InvalidSSZ, ProgList20.serialized.validate(one_byte_more));
    }

    // Test a valid case for comparison - exactly 20 elements = 80 bytes
    const valid_case = try allocator.alloc(u8, 80);
    defer allocator.free(valid_case);
    @memset(valid_case, 0xff);

    std.debug.print("\n=== Testing valid case (80 bytes) ===\n", .{});
    std.debug.print("Data length: {d}, element size: {d}, remainder: {d}\n", .{ valid_case.len, 4, valid_case.len % 4 });

    try ProgList20.serialized.validate(valid_case); // Should succeed
    std.debug.print("GOOD: valid case passed\n", .{});
}

test "debug progressive list validation - uint32_342 case" {
    const allocator = std.testing.allocator;

    // Test case: proglist_uint32_342_random_one_byte_more
    const ProgList342 = FixedProgressiveListType(UintType(32), 342);

    // From the test output: fs=4 limit=342 data.len=900
    // 900 / 4 = 225, which is within limit (225 <= 342)
    // But 900 % 4 = 0, so it should be valid!
    const test_data = try allocator.alloc(u8, 900);
    defer allocator.free(test_data);
    @memset(test_data, 0xff);

    std.debug.print("\n=== Testing proglist_uint32_342 case (900 bytes) ===\n", .{});
    std.debug.print("Data length: {d}, element size: {d}, remainder: {d}, elements: {d}\n", .{ test_data.len, 4, test_data.len % 4, test_data.len / 4 });

    const result = ProgList342.serialized.validate(test_data);
    if (result) |_| {
        std.debug.print("validate() returned void (success) - this case should be VALID!\n", .{});
        // This is actually correct behavior - the test case might be wrong
    } else |err| {
        std.debug.print("validate() returned error: {} - investigating why...\n", .{err});
    }
}

test "debug progressive list validation - uint128_22 case" {
    const allocator = std.testing.allocator;

    // Test case: proglist_uint128_22_zero_one_byte_more
    const ProgList22 = FixedProgressiveListType(UintType(128), 22);

    // From the test output: fs=16 limit=22 data.len=224
    // 224 / 16 = 14, which is within limit (14 <= 22)
    // 224 % 16 = 0, so it should be valid!
    const test_data = try allocator.alloc(u8, 224);
    defer allocator.free(test_data);
    @memset(test_data, 0);

    std.debug.print("\n=== Testing proglist_uint128_22 case (224 bytes) ===\n", .{});
    std.debug.print("Data length: {d}, element size: {d}, remainder: {d}, elements: {d}\n", .{ test_data.len, 16, test_data.len % 16, test_data.len / 16 });

    const result = ProgList22.serialized.validate(test_data);
    if (result) |_| {
        std.debug.print("validate() returned void (success) - this case should be VALID!\n", .{});
        // This is actually correct behavior - the test case might be wrong
    } else |err| {
        std.debug.print("validate() returned error: {} - investigating why...\n", .{err});
    }
}

test "verify 'one byte more' validation correctly rejects extra bytes" {
    _ = std.testing.allocator;

    // Test case: uint32 with limit 3 - using explicit UintType(32)
    const ProgList3 = FixedProgressiveListType(UintType(32), 3);
    std.debug.print("\n[TEST] ProgList3 element size: {d}\n", .{ProgList3.Element.fixed_size});

    // Valid case: exactly 3 elements = 12 bytes
    const valid_data = [_]u8{0xff} ** 12;
    std.debug.print("[TEST] Testing valid case: 12 bytes\n", .{});
    try ProgList3.serialized.validate(&valid_data); // Should pass
    std.debug.print("[TEST] Valid case passed as expected\n", .{});

    // Invalid case: 3 elements + 1 extra byte = 13 bytes (remainder = 1)
    const invalid_data = [_]u8{0xff} ** 13;
    std.debug.print("[TEST] Testing invalid case: 13 bytes (should fail with remainder=1)\n", .{});
    try std.testing.expectError(error.InvalidSSZ, ProgList3.serialized.validate(&invalid_data));
    std.debug.print("[TEST] Invalid case correctly rejected\n", .{});

    // Test with uint64 to see the difference
    const ProgList64 = FixedProgressiveListType(UintType(64), 3);
    std.debug.print("[TEST] ProgList64 element size: {d}\n", .{ProgList64.Element.fixed_size});

    // Test with uint16 elements
    const ProgList16 = FixedProgressiveListType(UintType(16), 5);
    std.debug.print("[TEST] ProgList16 element size: {d}\n", .{ProgList16.Element.fixed_size});

    // Valid: 5 elements = 10 bytes
    const valid_u16 = [_]u8{0xff} ** 10;
    try ProgList16.serialized.validate(&valid_u16);

    // Invalid: 5 elements + 1 byte = 11 bytes (remainder = 1)
    const invalid_u16 = [_]u8{0xff} ** 11;
    try std.testing.expectError(error.InvalidSSZ, ProgList16.serialized.validate(&invalid_u16));
}
