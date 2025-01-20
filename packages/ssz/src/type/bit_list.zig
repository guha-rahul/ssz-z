const std = @import("std");
const TypeKind = @import("type_kind.zig").TypeKind;
const BoolType = @import("bool.zig").BoolType;

pub fn BitList(comptime limit: comptime_int) type {
    return struct {
        data: std.ArrayListUnmanaged(u8),
        bit_len: usize,

        pub fn fromBitLen(allocator: std.mem.Allocator, bit_len: usize) !@This() {
            if (bit_len > limit) {
                return error.tooLarge;
            }

            const byte_len = std.math.divCeil(usize, bit_len, 8) catch unreachable;

            var data = try std.ArrayListUnmanaged(u8).initCapacity(allocator, byte_len);
            data.expandToCapacity();
            @memset(data.items, 0);
            return @This(){
                .data = data,
                .bit_len = bit_len,
            };
        }

        pub fn fromBoolSlice(allocator: std.mem.Allocator, bools: []const bool) !@This() {
            var bl = try @This().fromBitLen(allocator, bools.len);
            for (bools, 0..) |bit, i| {
                try bl.set(i, bit);
            }
            return bl;
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.data.deinit(allocator);
        }

        pub fn get(self: *const @This(), bit_index: usize) !bool {
            if (bit_index >= self.bit_len) {
                return error.OutOfRange;
            }

            const byte_idx = bit_index / 8;
            const offset_in_byte = bit_index % 8;
            const mask = 1 << offset_in_byte;
            return (self.data.items[byte_idx] & mask) == mask;
        }

        pub fn set(self: *@This(), allocator: std.mem.Allocator, bit_index: usize, bit: bool) !void {
            if (bit_index + 1 > self.bit_len) {
                try self.setBitLen(allocator, bit_index + 1);
            }
            try self.setAssumeCapacity(bit_index, bit);
        }

        pub fn setBitLen(self: *@This(), allocator: std.mem.Allocator, bit_len: usize) !void {
            if (bit_len > limit) {
                return error.tooLarge;
            }

            const byte_len = std.math.divCeil(usize, bit_len, 8) catch unreachable;
            try self.data.ensureTotalCapacity(allocator, byte_len);
            self.bit_len = bit_len;
        }

        /// Set bit value at index `bit_index`
        pub fn setAssumeCapacity(self: *@This(), bit_index: usize, bit: bool) !void {
            if (bit_index >= self.bit_len) {
                return error.OutOfRange;
            }

            const byte_index = bit_index / 8;
            const offset_in_byte: u3 = @intCast(bit_index % 8);
            const mask = @as(u8, 1) << offset_in_byte;
            var byte = self.data.items[byte_index];
            if (bit) {
                // For bit in byte, 1,0 OR 1 = 1
                // byte 100110
                // mask 010000
                // res  110110
                byte |= mask;
                self.data.items[byte_index] = byte;
            } else {
                // For bit in byte, 1,0 OR 1 = 0
                if ((byte & mask) == mask) {
                    // byte 110110
                    // mask 010000
                    // res  100110
                    byte ^= mask;
                    self.data.items[byte_index] = byte;
                } else {
                    // Ok, bit is already 0
                }
            }
        }
    };
}

pub fn BitListType(comptime _limit: comptime_int) type {
    return struct {
        pub const kind = TypeKind.vector;
        pub const Element: type = BoolType();
        pub const limit: usize = _limit;
        pub const Type: type = BitList(limit);
        pub const min_size: usize = 1;
        pub const max_size: usize = std.math.divCeil(usize, limit + 1, 8) catch unreachable;
        pub const chunk_count: usize = std.math.divCeil(usize, limit, 256) catch unreachable;

        pub fn serializedSize(value: *const Type) usize {
            return std.math.divCeil(usize, value.bit_len + 1, 8) catch unreachable;
        }

        pub fn serializeIntoBytes(value: *const Type, out: []u8) usize {
            const bit_len = value.bit_len + 1;
            const byte_len = std.math.divCeil(usize, bit_len, 8) catch unreachable;
            @memcpy(out, value.data.items);
            out[byte_len - 1] |= @as(u8, 1) << @intCast(bit_len % 8);
            return byte_len;
        }

        pub fn deserializeFromBytes(data: []const u8, allocator: std.mem.Allocator, out: *Type) !void {
            // ensure 1 bit and trailing zeros in last byte
            const last_byte = data[data.len - 1];

            const last_byte_clz = @clz(last_byte);
            if (last_byte_clz == 8) {
                return error.noPaddingBit;
            }
            const last_1_index: u3 = @intCast(7 - last_byte_clz);
            const bit_len = (data.len - 1) * 8 + last_1_index;
            if (bit_len > limit) {
                return error.tooLarge;
            }

            try out.setBitLen(allocator, bit_len);
            @memcpy(out.data.items, data);
            out.data.items[out.data.items.len - 1] ^= @as(u8, 1) << last_1_index;
        }

        pub fn validate(data: []const u8) !void {
            // ensure 1 bit and trailing zeros in last byte
            const last_byte = data[data.len - 1];

            const last_byte_clz = @clz(last_byte);
            if (last_byte_clz == 8) {
                return error.noPaddingBit;
            }
            const last_1_index: u3 = @intCast(7 - last_byte_clz);
            const bit_len = (data.len - 1) * 8 + last_1_index;
            if (bit_len > limit) {
                return error.tooLarge;
            }
        }
    };
}

test "BitListType - sanity" {
    const allocator = std.testing.allocator;
    const Bits = BitListType(40);
    var b: Bits.Type = try Bits.Type.fromBitLen(allocator, 30);
    defer b.deinit(allocator);

    try b.setAssumeCapacity(2, true);

    const b_buf = try allocator.alloc(u8, Bits.serializedSize(&b));
    defer allocator.free(b_buf);

    _ = Bits.serializeIntoBytes(&b, b_buf);
    try Bits.deserializeFromBytes(b_buf, allocator, &b);
}
