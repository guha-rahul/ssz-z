const std = @import("std");
const TypeKind = @import("type_kind.zig").TypeKind;
const BoolType = @import("bool.zig").BoolType;
const fromHex = @import("util").fromHex;

pub fn BitVector(comptime _length: comptime_int) type {
    const byte_len = std.math.divCeil(usize, _length, 8) catch unreachable;
    return struct {
        data: [byte_len]u8,

        pub const length = _length;

        pub fn init() @This() {
            return @This(){
                .data = [_]u8{0} ** byte_len,
            };
        }

        pub fn get(self: *const @This(), bit_index: usize) !bool {
            if (bit_index >= length) {
                return error.OutOfRange;
            }

            const byte_idx = bit_index / 8;
            const offset_in_byte: u3 = @intCast(bit_index % 8);
            const mask = @as(u8, 1) << offset_in_byte;
            return (self.data[byte_idx] & mask) == mask;
        }

        /// Set bit value at index `bit_index`
        pub fn set(self: *@This(), bit_index: usize, bit: bool) !void {
            if (bit_index >= length) {
                return error.OutOfRange;
            }

            const byte_index = bit_index / 8;
            const offset_in_byte: u3 = @intCast(bit_index % 8);
            const mask = @as(u8, 1) << offset_in_byte;
            var byte = self.data[byte_index];
            if (bit) {
                // For bit in byte, 1,0 OR 1 = 1
                // byte 100110
                // mask 010000
                // res  110110
                byte |= mask;
                self.data[byte_index] = byte;
            } else {
                // For bit in byte, 1,0 OR 1 = 0
                if ((byte & mask) == mask) {
                    // byte 110110
                    // mask 010000
                    // res  100110
                    byte ^= mask;
                    self.data[byte_index] = byte;
                } else {
                    // Ok, bit is already 0
                }
            }
        }
    };
}

pub fn BitVectorType(comptime _length: comptime_int) type {
    return struct {
        pub const kind = TypeKind.vector;
        pub const Element: type = BoolType();
        pub const length: usize = _length;
        pub const Type: type = BitVector(length);
        pub const fixed_size: usize = std.math.divCeil(usize, length, 8) catch unreachable;
        pub const chunk_count: usize = std.math.divCeil(usize, fixed_size, 32);

        pub fn serializeIntoBytes(value: *const Type, out: []u8) usize {
            @memcpy(out, &value.data);
            return length;
        }

        pub fn deserializeFromBytes(data: []const u8, out: *Type) !void {
            try validate(data);

            @memcpy(&out.data, data[0..fixed_size]);
        }

        pub fn validate(data: []const u8) !void {
            if (data.len != fixed_size) {
                return error.invalidLength;
            }

            // ensure trailing zeros
            if (@clz(data[fixed_size - 1]) >= @clz(@as(u8, length / 8))) {
                return error.trailingData;
            }
        }

        pub fn deserializeFromJson(source: *std.json.Scanner, out: *Type) !void {
            const hex_bytes = switch (try source.next()) {
                .string => |v| v,
                else => return error.InvalidJson,
            };
            const written = try fromHex(hex_bytes, &out.data);
            if (written != fixed_size) {
                return error.invalidLength;
            }
            // ensure trailing zeros
            if (@clz(out.data[fixed_size - 1]) >= @clz(@as(u8, length / 8))) {
                return error.trailingData;
            }
        }
    };
}

test "BitVectorType - sanity" {
    const length = 44;
    const Bits = BitVectorType(length);
    var b: Bits.Type = Bits.Type.init();
    try b.set(0, true);
    try b.set(length - 1, true);

    try std.testing.expectEqual(true, try b.get(0));
    for (1..length - 1) |i| {
        try std.testing.expectEqual(false, try b.get(i));
    }
    try std.testing.expectEqual(true, try b.get(length - 1));

    var b_buf: [Bits.fixed_size]u8 = undefined;
    _ = Bits.serializeIntoBytes(&b, &b_buf);
    try Bits.deserializeFromBytes(&b_buf, &b);
}
