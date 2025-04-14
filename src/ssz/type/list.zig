const std = @import("std");
const TypeKind = @import("type_kind.zig").TypeKind;
const isBasicType = @import("type_kind.zig").isBasicType;
const isFixedType = @import("type_kind.zig").isFixedType;
const OffsetIterator = @import("offsets.zig").OffsetIterator;

pub fn FixedListType(comptime ST: type, comptime _limit: comptime_int) type {
    comptime {
        if (!isFixedType(ST)) {
            @compileError("ST must be fixed type");
        }
    }
    return struct {
        pub const kind = TypeKind.list;
        pub const Element: type = ST;
        pub const limit: usize = _limit;
        pub const Type: type = std.ArrayListUnmanaged(Element.Type);
        pub const min_size: usize = 0;
        pub const max_size: usize = Element.fixed_size * limit;
        pub const chunk_count: usize = if (isBasicType(Element)) std.math.divCeil(usize, max_size, 32) catch unreachable else limit;

        pub fn defaultValue(allocator: std.mem.Allocator) !Type {
            return try Type.initCapacity(allocator, 0);
        }

        pub fn deinit(allocator: std.mem.Allocator, value: *Type) void {
            value.deinit(allocator);
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

        pub fn deserializedLength(data: []const u8) !usize {
            const len = try std.math.divExact(usize, data.len, Element.fixed_size);
            if (len > limit) {
                return error.gtLimit;
            }
            return len;
        }

        pub fn deserializeFromBytes(allocator: std.mem.Allocator, data: []const u8, out: *Type) !void {
            const len = try std.math.divExact(usize, data.len, Element.fixed_size);
            if (len > limit) {
                return error.gtLimit;
            }

            try out.ensureTotalCapacityPrecise(allocator, len);
            out.items.len = len;
            for (0..len) |i| {
                try Element.deserializeFromBytes(
                    data[i * Element.fixed_size .. (i + 1) * Element.fixed_size],
                    &out.items[i],
                );
            }
        }

        pub fn deserializeFromJson(allocator: std.mem.Allocator, source: *std.json.Scanner, out: *Type) !void {
            // start array token "["
            switch (try source.next()) {
                .array_begin => {},
                else => return error.InvalidJson,
            }

            for (0..limit + 1) |i| {
                switch (try source.peekNextTokenType()) {
                    .array_end => {
                        _ = try source.next();
                        return;
                    },
                    else => {},
                }

                try out.ensureUnusedCapacity(allocator, 1);
                out.expandToCapacity();
                try Element.deserializeFromJson(source, &out.items[i]);
            }
            return error.invalidLength;
        }

        pub fn validate(data: []const u8) !void {
            const len = try std.math.divExact(usize, data.len, Element.fixed_size);
            if (len > limit) {
                return error.gtLimit;
            }
            for (0..len) |i| {
                try Element.validate(data[i * Element.fixed_size .. (i + 1) * Element.fixed_size]);
            }
        }
    };
}

pub fn VariableListType(comptime ST: type, comptime _limit: comptime_int) type {
    comptime {
        if (isFixedType(ST)) {
            @compileError("ST must not be fixed type");
        }
    }
    return struct {
        pub const kind = TypeKind.list;
        pub const Element: type = ST;
        pub const limit: usize = _limit;
        pub const Type: type = std.ArrayListUnmanaged(Element.Type);
        pub const min_size: usize = 0;
        pub const max_size: usize = Element.max_size * limit + 4 * limit;
        pub const chunk_count: usize = limit;

        pub fn defaultValue(allocator: std.mem.Allocator) !Type {
            return try Type.initCapacity(allocator, 0);
        }

        pub fn deinit(allocator: std.mem.Allocator, value: *Type) void {
            value.deinit(allocator);
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

        pub fn deserializedLength(data: []const u8) !usize {
            var iterator = try OffsetIterator(@This()).init(data);
            return try iterator.firstOffset() / 4;
        }

        pub fn deserializeFromBytes(allocator: std.mem.Allocator, data: []const u8, out: *Type) !void {
            const offsets = try readVariableOffsets(allocator, data);
            defer allocator.free(offsets);

            const len = offsets.len - 1;

            try out.ensureTotalCapacityPrecise(allocator, len);
            out.items.len = len;
            for (0..len) |i| {
                try Element.deserializeFromBytes(allocator, data[offsets[i]..offsets[i + 1]], &out.items[i]);
            }
        }

        pub fn readVariableOffsets(allocator: std.mem.Allocator, data: []const u8) ![]u32 {
            var iterator = OffsetIterator(@This()).init(data);
            const first_offset = try iterator.next();
            const len = first_offset / 4;

            const offsets = try allocator.alloc(u32, len + 1);

            offsets[0] = first_offset;
            while (iterator.pos < len) {
                offsets[iterator.pos] = try iterator.next();
            }
            offsets[len] = @intCast(data.len);

            return offsets;
        }

        pub fn validate(data: []const u8) !void {
            var iterator = OffsetIterator(@This()).init(data);
            const first_offset = try iterator.next();
            const len = first_offset / 4;

            var curr_offset = first_offset;
            var prev_offset = first_offset;
            while (iterator.pos < len) {
                prev_offset = curr_offset;
                curr_offset = try iterator.next();

                try Element.validate(data[prev_offset..curr_offset]);
            }
            try Element.validate(data[curr_offset..data.len]);
        }

        pub fn deserializeFromJson(allocator: std.mem.Allocator, source: *std.json.Scanner, out: *Type) !void {
            // start array token "["
            switch (try source.next()) {
                .array_begin => {},
                else => return error.InvalidJson,
            }

            for (0..limit + 1) |i| {
                switch (try source.peekNextTokenType()) {
                    .array_end => {
                        _ = try source.next();
                        return;
                    },
                    else => {},
                }

                try out.ensureUnusedCapacity(allocator, 1);
                out.expandToCapacity();
                try Element.deserializeFromJson(allocator, source, &out.items[i]);
            }
            return error.invalidLength;
        }
    };
}

const UintType = @import("uint.zig").UintType;
const BoolType = @import("bool.zig").BoolType;

test "ListType - sanity" {
    const allocator = std.testing.allocator;

    // create a fixed list type and instance and round-trip serialize
    const Bytes = FixedListType(UintType(8), 32);

    var b: Bytes.Type = try Bytes.init(allocator);
    defer b.deinit(allocator);
    try b.append(allocator, 5);

    const b_buf = try allocator.alloc(u8, Bytes.serializedSize(&b));
    defer allocator.free(b_buf);

    _ = Bytes.serializeIntoBytes(&b, b_buf);
    try Bytes.deserializeFromBytes(allocator, b_buf, &b);

    // create a variable list type and instance and round-trip serialize
    const BytesBytes = VariableListType(Bytes, 32);
    var b2: BytesBytes.Type = try BytesBytes.init(allocator);
    defer b2.deinit(allocator);
    try b2.append(allocator, b);

    const b2_buf = try allocator.alloc(u8, BytesBytes.serializedSize(&b2));
    defer allocator.free(b2_buf);

    _ = BytesBytes.serializeIntoBytes(&b2, b2_buf);
    try BytesBytes.deserializeFromBytes(allocator, b2_buf, &b2);
}
