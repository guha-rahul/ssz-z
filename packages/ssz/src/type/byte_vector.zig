const std = @import("std");
const TypeKind = @import("type_kind.zig").TypeKind;
const UintType = @import("uint.zig").UintType;

pub fn ByteVectorType(comptime _length: comptime_int) type {
    return struct {
        pub const kind = TypeKind.vector;
        pub const Element: type = UintType(8);
        pub const length: usize = _length;
        pub const Type: type = [length]Element.Type;
        pub const fixed_size: usize = Element.fixed_size * length;
        pub const chunk_count: usize = std.math.divCeil(usize, fixed_size, 32) catch unreachable;

        pub fn serializeIntoBytes(value: *const Type, out: []u8) usize {
            @memcpy(out, value);
            return length;
        }

        pub fn deserializeFromBytes(data: []const u8, out: *Type) !void {
            @memcpy(out, data[0..fixed_size]);
        }
    };
}
