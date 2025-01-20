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

        pub fn deserializeFromBytes(data: []const u8, allocator: std.mem.Allocator, out: *Type) !void {
            const len = try std.math.divExact(usize, data.len, Element.fixed_size);
            if (len > limit) {
                return error.gtLimit;
            }

            try out.ensureTotalCapacity(allocator, len);
            for (0..len) |i| {
                try Element.deserializeFromBytes(
                    data[i * Element.fixed_size .. (i + 1) * Element.fixed_size],
                    &out.items[i],
                );
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
        pub const max_size: usize = Element.max_size * _limit;
        pub const chunk_count: usize = limit;

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

        pub fn deserializeFromBytes(data: []const u8, allocator: std.mem.Allocator, out: *Type) !void {
            const offsets = try readVariableOffsets(data, allocator);
            defer allocator.free(offsets);

            const len = offsets.len - 1;

            try out.ensureTotalCapacity(allocator, len);
            for (0..len) |i| {
                try Element.deserializeFromBytes(data[offsets[i]..offsets[i + 1]], allocator, &out.items[i]);
            }
        }

        pub fn readVariableOffsets(data: []const u8, allocator: std.mem.Allocator) ![]u32 {
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
    };
}

const UintType = @import("uint.zig").UintType;
const BoolType = @import("bool.zig").BoolType;

test "ListType - sanity" {
    const allocator = std.testing.allocator;

    // create a fixed list type and instance and round-trip serialize
    const Bytes = FixedListType(UintType(8), 32);

    var b: Bytes.Type = try std.ArrayListUnmanaged(Bytes.Element.Type).initCapacity(allocator, 0);
    defer b.deinit(allocator);
    try b.append(allocator, 5);

    const b_buf = try allocator.alloc(u8, Bytes.serializedSize(&b));
    defer allocator.free(b_buf);

    _ = Bytes.serializeIntoBytes(&b, b_buf);
    try Bytes.deserializeFromBytes(b_buf, allocator, &b);

    // create a variable list type and instance and round-trip serialize
    const BytesBytes = VariableListType(Bytes, 32);
    var b2: BytesBytes.Type = try std.ArrayListUnmanaged(BytesBytes.Element.Type).initCapacity(allocator, 0);
    defer b2.deinit(allocator);
    try b2.append(allocator, b);

    const b2_buf = try allocator.alloc(u8, BytesBytes.serializedSize(&b2));
    defer allocator.free(b2_buf);

    _ = BytesBytes.serializeIntoBytes(&b2, b2_buf);
    try BytesBytes.deserializeFromBytes(b2_buf, allocator, &b2);
}
