const std = @import("std");
const TypeKind = @import("type_kind.zig").TypeKind;
const UintType = @import("uint.zig").UintType;
const hexToBytes = @import("hex").hexToBytes;
const hexByteLen = @import("hex").hexByteLen;

pub fn isByteListType(ST: type) bool {
    return ST.kind == .list and ST.Element.kind == .uint and ST.Element.fixed_size == 1 and ST == ByteListType(ST.limit);
}

pub fn ByteListType(comptime _limit: comptime_int) type {
    return struct {
        pub const kind = TypeKind.list;
        pub const Element: type = UintType(8);
        pub const limit: usize = _limit;
        pub const Type: type = std.ArrayListUnmanaged(Element.Type);
        pub const min_size: usize = 0;
        pub const max_size: usize = Element.fixed_size * limit;
        pub const chunk_count: usize = std.math.divCeil(usize, max_size, 32) catch unreachable;

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
            @memcpy(out[0..value.items.len], value.items);
            return value.items.len;
        }

        pub fn deserializeFromBytes(allocator: std.mem.Allocator, data: []const u8, out: *Type) !void {
            if (data.len > limit) {
                return error.invalidLength;
            }

            try out.ensureTotalCapacityPrecise(allocator, data.len);
            out.items.len = data.len;
            @memcpy(out.items, data);
        }

        pub fn deserializeFromJson(allocator: std.mem.Allocator, source: *std.json.Scanner, out: *Type) !void {
            const hex_bytes = switch (try source.next()) {
                .string => |v| v,
                else => return error.InvalidJson,
            };

            const hex_bytes_len = hexByteLen(hex_bytes);
            if (hex_bytes_len > limit) {
                return error.InvalidJson;
            }

            try out.ensureTotalCapacityPrecise(allocator, hex_bytes_len);
            out.items.len = hex_bytes_len;
            _ = try hexToBytes(hex_bytes, out.items);
        }
    };
}
