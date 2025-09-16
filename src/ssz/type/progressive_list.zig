const std = @import("std");
const TypeKind = @import("type_kind.zig").TypeKind;
const isBasicType = @import("type_kind.zig").isBasicType;
const isFixedType = @import("type_kind.zig").isFixedType;

const hashing = @import("hashing");
const mixInLength = hashing.mixInLength;
const maxChunksToDepth = hashing.maxChunksToDepth;

const progressive = @import("progressive.zig");
const Node = @import("persistent_merkle_tree").Node;

pub fn ProgressiveListType(comptime Elem: type, comptime limit: comptime_int) type {
    comptime {
        if (limit <= 0) @compileError("limit must be > 0");
    }
    return struct {
        pub const kind = TypeKind.progressive_list;
        pub const Element = Elem;

        // In-memory representation
        pub const Type = std.ArrayListUnmanaged(Element.Type);

        pub const min_size: usize = 0;
        pub const max_size: usize = if (isFixedType(Element))
            Element.fixed_size * limit
        else
            Element.max_size * limit + 4 * limit;

        pub const default_value: Type = Type.empty;

        pub fn deinit(a: std.mem.Allocator, v: *Type) void {
            if (!isBasicType(Element)) {
                for (v.items) |*e| Element.deinit(a, e);
            }
            v.deinit(a);
        }

        pub fn equals(a: *const Type, b: *const Type) bool {
            if (a.items.len != b.items.len) return false;
            for (a.items, b.items) |ae, be| {
                if (!Element.equals(&ae, &be)) return false;
            }
            return true;
        }

        pub fn serializedSize(v: *const Type) usize {
            if (comptime isFixedType(Element)) {
                return v.items.len * Element.fixed_size;
            } else {
                var size: usize = v.items.len * 4;
                for (v.items) |e| size += Element.serializedSize(&e);
                return size;
            }
        }

        pub fn serializeIntoBytes(v: *const Type, out: []u8) usize {
            if (isFixedType(Element)) {
                var w: usize = 0;
                for (v.items) |e| w += Element.serializeIntoBytes(&e, out[w..]);
                return w;
            } else {
                var var_idx: usize = v.items.len * 4;
                for (v.items, 0..) |e, i| {
                    std.mem.writeInt(u32, out[i * 4 ..][0..4], @intCast(var_idx), .little);
                    var_idx += Element.serializeIntoBytes(&e, out[var_idx..]);
                }
                return var_idx;
            }
        }

        pub fn serializeIntoJson(allocator: std.mem.Allocator, writer: anytype, in: *const Type) !void {
            try writer.beginArray();
            if (comptime isFixedType(Element)) {
                for (in.items) |e| {
                    try Element.serializeIntoJson(writer, &e);
                }
            } else {
                for (in.items) |e| {
                    try Element.serializeIntoJson(allocator, writer, &e);
                }
            }
            try writer.endArray();
        }

        pub fn deserializeFromJson(allocator: std.mem.Allocator, source: *std.json.Scanner, out: *Type) !void {
            switch (try source.next()) {
                .array_begin => {},
                else => return error.InvalidJson,
            }

            var i: usize = 0;
            while (i <= limit) : (i += 1) {
                switch (try source.peekNextTokenType()) {
                    .array_end => {
                        _ = try source.next();
                        return;
                    },
                    else => {},
                }

                _ = try out.addOne(allocator);
                out.items[i] = Element.default_value;
                if (comptime isFixedType(Element)) {
                    try Element.deserializeFromJson(source, &out.items[i]);
                } else {
                    try Element.deserializeFromJson(allocator, source, &out.items[i]);
                }
            }
            return error.invalidLength;
        }

        pub fn deserializeFromBytes(
            allocator: std.mem.Allocator,
            data: []const u8,
            out: *Type,
        ) !void {
            if (comptime isFixedType(Element)) {
                if (data.len % Element.fixed_size != 0) return error.InvalidSize;
                const n = data.len / Element.fixed_size;
                if (n > limit) return error.gtLimit;

                try out.resize(allocator, n);
                @memset(out.items[0..n], Element.default_value);

                var i: usize = 0;
                while (i < n) : (i += 1) {
                    try Element.deserializeFromBytes(
                        data[i * Element.fixed_size .. (i + 1) * Element.fixed_size],
                        &out.items[i],
                    );
                }
            } else {
                const VL = @import("list.zig").VariableListType(Element, limit);
                const offs = try VL.readVariableOffsets(allocator, data);
                defer allocator.free(offs);

                const n = offs.len - 1;
                if (n > limit) return error.gtLimit;

                try out.resize(allocator, n);
                @memset(out.items[0..n], Element.default_value);

                var i: usize = 0;
                while (i < n) : (i += 1) {
                    try Element.deserializeFromBytes(
                        allocator,
                        data[offs[i]..offs[i + 1]],
                        &out.items[i],
                    );
                }
            }
        }

        /// Value path hashing delegates to the serialized path for consistency
        pub fn hashTreeRoot(a: std.mem.Allocator, v: *const Type, out: *[32]u8) !void {
            const total = serializedSize(v);
            const buf = try a.alloc(u8, total);
            defer a.free(buf);
            _ = serializeIntoBytes(v, buf);
            try serialized.hashTreeRoot(a, buf, out);
        }

        pub const serialized = struct {
            pub fn validate(data: []const u8) !void {
                if (comptime isFixedType(Element)) {
                    if (data.len % Element.fixed_size != 0) return error.InvalidSize;
                } else {
                    // Rely on VariableListType iterator validation for offsets
                    const VL = @import("list.zig").VariableListType(Element, limit);
                    const it = @import("offsets.zig").OffsetIterator(VL).init(data);
                    _ = try it.firstOffset();
                }
            }

            pub fn length(data: []const u8) !usize {
                if (comptime isFixedType(Element)) {
                    if (data.len % Element.fixed_size != 0) return error.InvalidSize;
                    return data.len / Element.fixed_size;
                } else {
                    if (data.len == 0) return 0;
                    const VL = @import("list.zig").VariableListType(Element, limit);
                    var it = @import("serialized.zig").OffsetIterator(VL).init(data);
                    return try it.firstOffset() / 4;
                }
            }

            pub fn hashTreeRoot(a: std.mem.Allocator, data: []const u8, out: *[32]u8) !void {
                const len = try length(data);
                if (len == 0) {
                    @memset(out, 0);
                    mixInLength(0, out);
                    return;
                }

                const leaf_count: usize = if (comptime isBasicType(Element))
                    (data.len + 31) / 32
                else
                    len;

                var offs_opt: ?[]usize = null;
                defer if (offs_opt) |o| a.free(o);
                if (comptime (!isBasicType(Element) and !isFixedType(Element))) {
                    const VL = @import("list.zig").VariableListType(Element, limit);
                    offs_opt = try VL.readVariableOffsets(a, data);
                }

                const Ctx = struct { allocator: std.mem.Allocator, data: []const u8, offs: ?[]usize };
                var ctx = Ctx{ .allocator = a, .data = data, .offs = offs_opt };

                const getLeaf = struct {
                    fn f(pctx: ?*anyopaque, index: usize, leaf_out: *[32]u8) !void {
                        const c: *Ctx = @ptrCast(@alignCast(pctx.?));
                        if (comptime isBasicType(Element)) {
                            const start = index * 32;
                            const end = @min(start + 32, c.data.len);
                            @memset(leaf_out, 0);
                            if (start < end) @memcpy(leaf_out[0 .. end - start], c.data[start..end]);
                            return;
                        }
                        if (comptime isFixedType(Element)) {
                            const sz = Element.fixed_size;
                            const off = index * sz;
                            var tmp: [32]u8 = undefined;
                            try Element.serialized.hashTreeRoot(c.data[off .. off + sz], &tmp);
                            @memcpy(leaf_out, &tmp);
                            return;
                        }
                        const offs = c.offs.?;
                        var tmp: [32]u8 = undefined;
                        try Element.serialized.hashTreeRoot(c.allocator, c.data[offs[index]..offs[index + 1]], &tmp);
                        @memcpy(leaf_out, &tmp);
                    }
                }.f;

                try progressive.merkleizeByLeafFn(a, leaf_count, getLeaf, &ctx, out);
                mixInLength(len, out);
            }
        };

        pub const tree = struct {
            pub fn length(node: Node.Id, pool: *Node.Pool) !usize {
                const right = try node.getRight(pool);
                const hash = right.getRoot(pool);
                return std.mem.readInt(usize, hash[0..8], .little);
            }

            pub fn toValue(allocator: std.mem.Allocator, node: Node.Id, pool: *Node.Pool, out: *Type) !void {
                const len = try length(node, pool);
                if (len == 0) {
                    try out.resize(allocator, 0);
                    return;
                }

                if (comptime isBasicType(Element)) {
                    const total_bytes = len * Element.fixed_size;
                    const chunk_count = (total_bytes + 31) / 32;
                    const depth = maxChunksToDepth(chunk_count);
                    const nodes = try allocator.alloc(Node.Id, chunk_count);
                    defer allocator.free(nodes);
                    try node.getNodesAtDepth(pool, depth + 1, 0, nodes);

                    var bytes = try allocator.alloc(u8, total_bytes);
                    defer allocator.free(bytes);
                    for (0..chunk_count) |i| {
                        const start_idx = i * 32;
                        const remaining_bytes = total_bytes - start_idx;
                        const to_copy = @min(remaining_bytes, 32);
                        if (to_copy > 0) {
                            @memcpy(bytes[start_idx..][0..to_copy], nodes[i].getRoot(pool)[0..to_copy]);
                        }
                    }
                    out.* = Type.empty;
                    try ProgressiveListType(Element, limit).deserializeFromBytes(allocator, bytes, out);
                } else if (comptime isFixedType(Element)) {
                    const chunk_count = len;
                    const depth = maxChunksToDepth(chunk_count);
                    const nodes = try allocator.alloc(Node.Id, chunk_count);
                    defer allocator.free(nodes);
                    try node.getNodesAtDepth(pool, depth + 1, 0, nodes);

                    try out.resize(allocator, len);
                    @memset(out.items, Element.default_value);
                    for (0..len) |i| {
                        try Element.tree.toValue(nodes[i], pool, &out.items[i]);
                    }
                } else {
                    const chunk_count = len;
                    const depth = maxChunksToDepth(chunk_count);
                    const nodes = try allocator.alloc(Node.Id, chunk_count);
                    defer allocator.free(nodes);
                    try node.getNodesAtDepth(pool, depth + 1, 0, nodes);

                    try out.resize(allocator, len);
                    @memset(out.items, Element.default_value);
                    for (0..len) |i| {
                        try Element.tree.toValue(allocator, nodes[i], pool, &out.items[i]);
                    }
                }
            }

            pub fn fromValue(allocator: std.mem.Allocator, pool: *Node.Pool, value: *const Type) !Node.Id {
                const len = value.items.len;
                if (len == 0) {
                    return try pool.createBranch(@enumFromInt(0), @enumFromInt(0), false);
                }

                if (comptime isBasicType(Element)) {
                    const total = ProgressiveListType(Element, limit).serializedSize(value);
                    var buf = try allocator.alloc(u8, total);
                    defer allocator.free(buf);
                    _ = ProgressiveListType(Element, limit).serializeIntoBytes(value, buf);

                    const chunk_count = (total + 31) / 32;
                    const depth = maxChunksToDepth(chunk_count);
                    const nodes = try allocator.alloc(Node.Id, chunk_count);
                    defer allocator.free(nodes);
                    for (0..chunk_count) |i| {
                        var leaf_buf = [_]u8{0} ** 32;
                        const start_idx = i * 32;
                        const remaining_bytes = total - start_idx;
                        const to_copy = @min(remaining_bytes, 32);
                        if (to_copy > 0) {
                            @memcpy(leaf_buf[0..to_copy], buf[start_idx..][0..to_copy]);
                        }
                        nodes[i] = try pool.createLeaf(&leaf_buf, false);
                    }
                    return try pool.createBranch(
                        try Node.fillWithContents(pool, nodes, depth, false),
                        try pool.createLeafFromUint(len, false),
                        false,
                    );
                } else if (comptime isFixedType(Element)) {
                    const chunk_count = len;
                    const depth = maxChunksToDepth(chunk_count);
                    const nodes = try allocator.alloc(Node.Id, chunk_count);
                    defer allocator.free(nodes);
                    for (0..chunk_count) |i| {
                        nodes[i] = try Element.tree.fromValue(pool, &value.items[i]);
                    }
                    return try pool.createBranch(
                        try Node.fillWithContents(pool, nodes, depth, false),
                        try pool.createLeafFromUint(len, false),
                        false,
                    );
                } else {
                    const chunk_count = len;
                    const depth = maxChunksToDepth(chunk_count);
                    const nodes = try allocator.alloc(Node.Id, chunk_count);
                    defer allocator.free(nodes);
                    for (0..chunk_count) |i| {
                        nodes[i] = try Element.tree.fromValue(allocator, pool, &value.items[i]);
                    }
                    return try pool.createBranch(
                        try Node.fillWithContents(pool, nodes, depth, false),
                        try pool.createLeafFromUint(len, false),
                        false,
                    );
                }
            }
        };
    };
}

// Convenience wrappers
pub fn ProgressiveByteListType(comptime limit: comptime_int) type {
    const U8 = @import("uint.zig").UintType(8);
    return ProgressiveListType(U8, limit);
}

// Progressive bitlist packs bits plus a termination bit and mixes in bit length
pub fn ProgressiveBitListType(comptime limit: comptime_int) type {
    return struct {
        pub const kind = TypeKind.progressive_list;
        pub const Type = struct {
            data: std.ArrayListUnmanaged(u8),
            bit_len: usize,

            pub fn deinit(self: *Type, a: std.mem.Allocator) void {
                self.data.deinit(a);
            }
        };

        pub const default_value: Type = .{ .data = .{}, .bit_len = 0 };

        pub fn deinit(a: std.mem.Allocator, v: *Type) void {
            v.data.deinit(a);
        }
        pub fn equals(a: *const Type, b: *const Type) bool {
            return a.bit_len == b.bit_len and std.mem.eql(u8, a.data.items, b.data.items);
        }

        pub fn serializedSize(v: *const Type) usize {
            return (v.bit_len + 1 + 7) / 8;
        }

        pub fn serializeIntoBytes(v: *const Type, out: []u8) usize {
            const bit_len = v.bit_len + 1; // include termination bit
            const byte_len = (bit_len + 7) / 8;
            if (v.bit_len % 8 == 0) {
                @memcpy(out[0 .. byte_len - 1], v.data.items);
                out[byte_len - 1] = 1;
            } else {
                @memcpy(out[0..byte_len], v.data.items);
                out[byte_len - 1] |= @as(u8, 1) << @intCast((bit_len - 1) % 8);
            }
            return byte_len;
        }

        pub fn deserializeFromBytes(a: std.mem.Allocator, data: []const u8, out: *Type) !void {
            if (data.len == 0) return error.InvalidSize;

            const last_byte = data[data.len - 1];
            const last_byte_clz = @clz(last_byte);
            if (last_byte_clz == 8) return error.MissingTerminationBit;
            const last_1_index: u3 = @intCast(7 - last_byte_clz);
            const bit_len = (data.len - 1) * 8 + last_1_index;
            if (bit_len > limit) return error.gtLimit;

            out.* = .{ .data = .{}, .bit_len = bit_len };
            try out.data.resize(a, (bit_len + 7) / 8);
            if (bit_len == 0) return;
            if (bit_len % 8 == 0) {
                @memcpy(out.data.items, data[0 .. data.len - 1]);
            } else {
                @memcpy(out.data.items, data);
                out.data.items[out.data.items.len - 1] ^= @as(u8, 1) << last_1_index;
            }
        }

        pub fn serializeIntoJson(a: std.mem.Allocator, writer: anytype, v: *const Type) !void {
            const bytes = try a.alloc(u8, serializedSize(v));
            defer a.free(bytes);
            _ = serializeIntoBytes(v, bytes);
            const hex_len = @import("hex").hexLenFromBytes(bytes);
            const buf = try a.alloc(u8, hex_len);
            defer a.free(buf);
            _ = try @import("hex").bytesToHex(buf, bytes);
            try writer.print("\"{s}\"", .{buf});
        }

        pub fn deserializeFromJson(a: std.mem.Allocator, source: *std.json.Scanner, out: *Type) !void {
            const hex_bytes = switch (try source.next()) {
                .string => |v| v,
                else => return error.InvalidJson,
            };
            const byte_len = @import("hex").byteLenFromHex(hex_bytes);
            const buf = try a.alloc(u8, byte_len);
            defer a.free(buf);
            _ = try @import("hex").hexToBytes(buf, hex_bytes);
            try deserializeFromBytes(a, buf, out);
        }

        fn encBytes(bit_len: usize) usize {
            return (bit_len + 1 + 7) / 8;
        }

        pub fn hashTreeRoot(a: std.mem.Allocator, v: *const Type, out: *[32]u8) !void {
            // Hash the raw bit data (no termination bit) and mix in bit length
            const byte_len = (v.bit_len + 7) / 8;
            const chunk_count = (byte_len + 31) / 32;
            const even_chunks = ((chunk_count + 1) / 2) * 2;
            const chunks = try a.alloc([32]u8, even_chunks);
            defer a.free(chunks);
            @memset(chunks, [_]u8{0} ** 32);
            if (byte_len > 0) {
                const bytes: []u8 = @as([]u8, @ptrCast(chunks));
                @memcpy(bytes[0..byte_len], v.data.items[0..byte_len]);
            }
            try progressive.merkleizeChunks(a, chunks, out);
            mixInLength(v.bit_len, out);
        }

        pub const serialized = struct {
            pub fn validate(data: []const u8) !void {
                if (data.len == 0) return error.InvalidSize;
                var any_set = false;
                inline for (0..8) |i| {
                    if (((data[data.len - 1] >> @intCast(i)) & 1) == 1) {
                        any_set = true;
                    }
                }
                if (!any_set) return error.MissingTerminationBit;
                // limit check
                var pos: u3 = 0;
                inline for (0..8) |i| {
                    if (((data[data.len - 1] >> @intCast(i)) & 1) == 1) pos = @intCast(i);
                }
                const bit_len = (data.len - 1) * 8 + pos;
                if (bit_len > limit) return error.gtLimit;
            }
            pub fn length(data: []const u8) !usize {
                if (data.len == 0) return error.InvalidSize;
                var pos: u3 = 0;
                inline for (0..8) |i| {
                    if (((data[data.len - 1] >> @intCast(i)) & 1) == 1) {
                        pos = @intCast(i);
                    }
                }
                return (data.len - 1) * 8 + pos;
            }
            pub fn hashTreeRoot(a: std.mem.Allocator, data: []const u8, out: *[32]u8) !void {
                // Interpret data as bitlist with termination bit; hash without the termination bit
                const bit_len = try length(data);
                const byte_len = (bit_len + 7) / 8;
                const chunk_count = (byte_len + 31) / 32;
                const even_chunks = ((chunk_count + 1) / 2) * 2;
                const chunks = try a.alloc([32]u8, even_chunks);
                defer a.free(chunks);
                @memset(chunks, [_]u8{0} ** 32);

                if (byte_len > 0) {
                    const bytes: []u8 = @as([]u8, @ptrCast(chunks));
                    if (bit_len % 8 == 0) {
                        @memcpy(bytes[0 .. data.len - 1], data[0 .. data.len - 1]);
                    } else {
                        @memcpy(bytes[0..data.len], data);
                        // remove termination bit
                        bytes[data.len - 1] ^=
                            @as(u8, 1) << @intCast(@as(u3, @intCast((bit_len % 8))));
                    }
                }

                try progressive.merkleizeChunks(a, chunks, out);
                mixInLength(bit_len, out);
            }
        };

        pub const tree = struct {
            pub fn length(node: Node.Id, pool: *Node.Pool) !usize {
                const right = try node.getRight(pool);
                const hash = right.getRoot(pool);
                return std.mem.readInt(usize, hash[0..8], .little);
            }

            pub fn toValue(allocator: std.mem.Allocator, node: Node.Id, pool: *Node.Pool, out: *Type) !void {
                const bits = try length(node, pool);
                out.* = .{ .data = .{}, .bit_len = bits };
                const byte_len = (bits + 7) / 8;
                try out.data.resize(allocator, byte_len);
                if (bits == 0 or byte_len == 0) return;

                const chunk_count = (byte_len + 31) / 32;
                const depth = maxChunksToDepth(chunk_count);
                const nodes = try allocator.alloc(Node.Id, chunk_count);
                defer allocator.free(nodes);
                try node.getNodesAtDepth(pool, depth + 1, 0, nodes);

                var copied: usize = 0;
                for (0..chunk_count) |i| {
                    const to_copy = @min(byte_len - copied, 32);
                    if (to_copy == 0) break;
                    @memcpy(out.data.items[copied..][0..to_copy], nodes[i].getRoot(pool)[0..to_copy]);
                    copied += to_copy;
                }
            }

            pub fn fromValue(allocator: std.mem.Allocator, pool: *Node.Pool, value: *const Type) !Node.Id {
                const byte_len = (value.bit_len + 7) / 8;
                const chunk_count = (byte_len + 31) / 32;
                if (chunk_count == 0) {
                    return try pool.createBranch(@enumFromInt(0), @enumFromInt(0), false);
                }

                const depth = maxChunksToDepth(chunk_count);
                const nodes = try allocator.alloc(Node.Id, chunk_count);
                defer allocator.free(nodes);
                var copied: usize = 0;
                for (0..chunk_count) |i| {
                    var leaf_buf = [_]u8{0} ** 32;
                    const to_copy = @min(byte_len - copied, 32);
                    if (to_copy > 0) {
                        @memcpy(leaf_buf[0..to_copy], value.data.items[copied..][0..to_copy]);
                        copied += to_copy;
                    }
                    nodes[i] = try pool.createLeaf(&leaf_buf, false);
                }
                return try pool.createBranch(
                    try Node.fillWithContents(pool, nodes, depth, false),
                    try pool.createLeafFromUint(value.bit_len, false),
                    false,
                );
            }
        };

        // Keep the limit in the type to avoid unused parameter warning
        pub const limit_value: usize = limit;
    };
}
