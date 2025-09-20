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
                _ = serializeIntoBytes(value, @ptrCast(chunks));
                if (chunks.len > 0) {
                    std.debug.print("[PGL value] first_leaf={s}\n", .{std.fmt.fmtSliceHexLower(chunks[0][0..])});
                }
            } else {
                for (value.items, 0..) |element, i| {
                    try Element.hashTreeRoot(&element, &chunks[i]);
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
                std.debug.print("[PGL fixed.validate] fs={d} limit={d} data.len={d}\n", .{ Element.fixed_size, limit, data.len });
                if (data.len % Element.fixed_size != 0) {
                    std.debug.print("[PGL fixed.validate] non-multiple: rem={d}\n", .{data.len % Element.fixed_size});
                    return error.InvalidSSZ;
                }
                if (limit == 0) {
                    if (data.len == 0) return; // only empty is valid
                    return error.InvalidSSZ;
                }
                const len = data.len / Element.fixed_size;
                std.debug.print("[PGL fixed.validate] len={d}\n", .{len});
                if (len > limit) {
                    std.debug.print("[PGL fixed.validate] over-limit len={d} > limit={d}\n", .{ len, limit });
                    return error.InvalidSSZ;
                }
                for (0..len) |i| {
                    try Element.serialized.validate(data[i * Element.fixed_size .. (i + 1) * Element.fixed_size]);
                }
            }

            pub fn length(data: []const u8) !usize {
                std.debug.print("[PGL fixed.length] fs={d} limit={d} data.len={d}\n", .{ Element.fixed_size, limit, data.len });
                if (data.len % Element.fixed_size != 0) {
                    std.debug.print("[PGL fixed.length] non-multiple: rem={d}\n", .{data.len % Element.fixed_size});
                    return error.InvalidSSZ;
                }
                if (limit == 0) {
                    if (data.len == 0) return 0; // only empty is valid
                    return error.InvalidSSZ;
                }
                const len = data.len / Element.fixed_size;
                std.debug.print("[PGL fixed.length] len={d}\n", .{len});
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
                    @memcpy(@as([]u8, @ptrCast(chunks))[0..data.len], data);
                    if (chunks.len > 0) {
                        std.debug.print("[PGL ser] first_leaf={s}\n", .{std.fmt.fmtSliceHexLower(chunks[0][0..])});
                    }
                } else {
                    for (0..len) |i| {
                        try Element.serialized.hashTreeRoot(
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

                try progressive.getNodes(pool, try node.getLeft(pool), nodes);

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
                if (chunk_count == 0) {
                    return try pool.createBranch(
                        @enumFromInt(0),
                        @enumFromInt(0),
                        false,
                    );
                }

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
                    }
                } else {
                    for (0..chunk_count) |i| {
                        nodes[i] = try Element.tree.fromValue(pool, &value.items[i]);
                    }
                }
                return try pool.createBranch(
                    try progressive.fillWithContents(pool, nodes, false),
                    try pool.createLeafFromUint(len, false),
                    false,
                );
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
                var iterator = OffsetIterator(Self).init(data);
                if (data.len == 0) return;
                if (limit == 0) return error.InvalidSSZ;
                if (data.len < 4) return error.InvalidSSZ;
                const first_offset = try iterator.next();
                const len = first_offset / 4;

                if (len > limit) {
                    return error.gtLimit;
                }

                var curr_offset = first_offset;
                var prev_offset = first_offset;
                while (iterator.pos < len) {
                    prev_offset = curr_offset;
                    curr_offset = try iterator.next();

                    try Element.serialized.validate(data[prev_offset..curr_offset]);
                }
                try Element.serialized.validate(data[curr_offset..data.len]);
            }

            pub fn length(data: []const u8) !usize {
                if (data.len == 0) {
                    return 0;
                }
                if (limit == 0) return error.InvalidSSZ;
                if (data.len < 4) return error.InvalidSSZ;
                var iterator = OffsetIterator(Self).init(data);
                const first_offset = try iterator.firstOffset();
                if (first_offset > data.len) return error.InvalidSSZ;
                const len = first_offset / 4;
                if (len > limit) {
                    return error.gtLimit;
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

                try progressive.getNodes(pool, try node.getLeft(pool), nodes);

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
                if (chunk_count == 0) {
                    return try pool.createBranch(
                        @enumFromInt(0),
                        @enumFromInt(0),
                        false,
                    );
                }

                const nodes = try allocator.alloc(Node.Id, chunk_count);
                defer allocator.free(nodes);
                for (0..chunk_count) |i| {
                    nodes[i] = try Element.tree.fromValue(allocator, pool, &value.items[i]);
                }
                return try pool.createBranch(
                    try progressive.fillWithContents(pool, nodes, false),
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

test "ProgressiveList validation should fail for invalid size" {
    const Uint64List = FixedProgressiveListType(UintType(64), 1024);

    // Test data that's not divisible by 8 (uint64 size)
    const invalid_data = [_]u8{ 1, 2, 3, 4, 5, 6, 7 }; // 7 bytes, not divisible by 8
    try std.testing.expectError(error.InvalidSSZ, Uint64List.serialized.validate(&invalid_data));

    // Test valid data (should pass)
    const valid_data = [_]u8{0} ** 8; // 1 element, should be valid
    try Uint64List.serialized.validate(&valid_data);

    // Test the specific failing case from the tests
    const test_case_data = [_]u8{0xff} ** 112; // 14 elements, should be valid
    try Uint64List.serialized.validate(&test_case_data);

    // Test what SHOULD be the invalid case
    const should_be_invalid = [_]u8{0xff} ** 177; // 22*8+1 bytes, not divisible by 8
    try std.testing.expectError(error.InvalidSSZ, Uint64List.serialized.validate(&should_be_invalid));

    // Test limit validation
    const SmallUint64List = FixedProgressiveListType(UintType(64), 10);
    const too_many_elements = [_]u8{0xff} ** (11 * 8); // 11 elements, exceeds limit of 10

    try std.testing.expectError(error.InvalidSSZ, SmallUint64List.serialized.validate(&too_many_elements));

    // Debug test - check a "one byte more" case like the failing tests
    const Uint32List = FixedProgressiveListType(UintType(32), 1024);
    const one_byte_more = [_]u8{0xff} ** 5; // 5 bytes, not divisible by 4
    std.debug.print("Testing one_byte_more case...\n", .{});
    try std.testing.expectError(error.InvalidSSZ, Uint32List.serialized.validate(&one_byte_more));

    // Debug test - check the exact failing test case
    const test_case_failing = [_]u8{0} ** 56; // 56 bytes = 14 uint32s, should be valid
    std.debug.print("Testing exact failing case (56 bytes)...\n", .{});
    try Uint32List.serialized.validate(&test_case_failing); // This should pass

    // What about exactly one byte more than the test case?
    const test_case_failing_plus_one = [_]u8{0} ** 57; // 57 bytes, not divisible by 4
    std.debug.print("Testing exact failing case + 1 byte (57 bytes)...\n", .{});
    try std.testing.expectError(error.InvalidSSZ, Uint32List.serialized.validate(&test_case_failing_plus_one));
}

test "FixedProgressiveList zero limit: only empty is valid" {
    const allocator = std.testing.allocator;
    const U32Zero = FixedProgressiveListType(UintType(32), 0);

    // validate empty
    try U32Zero.serialized.validate(&[_]u8{});
    try std.testing.expectEqual(@as(usize, 0), try U32Zero.serialized.length(&[_]u8{}));

    // any non-empty buffer is invalid
    try std.testing.expectError(error.InvalidSSZ, U32Zero.serialized.validate(&[_]u8{ 0, 0, 0, 0 }));
    try std.testing.expectError(error.InvalidSSZ, U32Zero.serialized.length(&[_]u8{ 0, 0, 0, 0 }));

    // deserialize respects validate first
    var out: U32Zero.Type = U32Zero.Type.empty;
    defer out.deinit(allocator);
    try U32Zero.deserializeFromBytes(allocator, &[_]u8{}, &out);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try std.testing.expectError(error.InvalidSSZ, U32Zero.deserializeFromBytes(allocator, &[_]u8{ 0, 0, 0, 0 }, &out));
}

test "VariableProgressiveList zero limit: only empty is valid" {
    const allocator = std.testing.allocator;
    // Element type is a variable-sized ProgressiveList from earlier test
    const Bytes = FixedProgressiveListType(UintType(8), 1024);
    const VarZero = VariableProgressiveListType(Bytes, 0);

    // validate empty
    try VarZero.serialized.validate(&[_]u8{});
    try std.testing.expectEqual(@as(usize, 0), try VarZero.serialized.length(&[_]u8{}));

    // any non-empty buffer is invalid (no header allowed when limit==0)
    try std.testing.expectError(error.InvalidSSZ, VarZero.serialized.validate(&[_]u8{ 0, 0, 0, 0 }));
    try std.testing.expectError(error.InvalidSSZ, VarZero.serialized.length(&[_]u8{ 0, 0, 0, 0 }));

    // deserialize respects validate first
    var out: VarZero.Type = VarZero.Type.empty;
    defer VarZero.deinit(allocator, &out);
    try VarZero.deserializeFromBytes(allocator, &[_]u8{}, &out);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
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
                std.mem.writeInt(u16, leaves[chunk_i][off .. off + 2], @as(u16, @intCast(j)), .little);
            }
        }
        var rc: [32]u8 = undefined;
        try progressive.merkleizeChunks(gpa, leaves, &rc);

        if (!(std.mem.eql(u8, &rv, &rs) and std.mem.eql(u8, &rv, &rc))) {
            std.debug.print("[DBG list u16 n={d}] value={s}\n", .{ n, std.fmt.fmtSliceHexLower(rv[0..]) });
            std.debug.print("[DBG list u16 n={d}] serial={s}\n", .{ n, std.fmt.fmtSliceHexLower(rs[0..]) });
            std.debug.print("[DBG list u16 n={d}] conts ={s}\n", .{ n, std.fmt.fmtSliceHexLower(rc[0..]) });
        }

        try testing.expect(std.mem.eql(u8, &rv, &rs));
        try testing.expect(std.mem.eql(u8, &rv, &rc));
    }
}
