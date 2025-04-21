const std = @import("std");
const TypeKind = @import("type_kind.zig").TypeKind;
const UintType = @import("uint.zig").UintType;
const hexToBytes = @import("hex").hexToBytes;
const hexByteLen = @import("hex").hexByteLen;
const merkleize = @import("hashing").merkleize;
const mixInLength = @import("hashing").mixInLength;
const maxChunksToDepth = @import("hashing").maxChunksToDepth;

pub fn isByteListType(ST: type) bool {
    return ST.kind == .list and ST.Element.kind == .uint and ST.Element.fixed_size == 1 and ST == ByteListType(ST.limit);
}

pub fn ByteListType(comptime _limit: comptime_int) type {
    comptime {
        if (_limit <= 0) {
            @compileError("limit must be greater than 0");
        }
    }
    return struct {
        pub const kind = TypeKind.list;
        pub const Element: type = UintType(8);
        pub const limit: usize = _limit;
        pub const Type: type = std.ArrayListUnmanaged(Element.Type);
        pub const min_size: usize = 0;
        pub const max_size: usize = Element.fixed_size * limit;
        pub const max_chunk_count: usize = std.math.divCeil(usize, max_size, 32) catch unreachable;
        pub const chunk_depth: u8 = maxChunksToDepth(max_chunk_count);

        pub const default_value: Type = Type.empty;

        pub fn deinit(allocator: std.mem.Allocator, value: *Type) void {
            value.deinit(allocator);
        }

        pub fn chunkCount(value: *const Type) usize {
            return (value.items.len + 31) / 32;
        }

        pub fn hashTreeRoot(allocator: std.mem.Allocator, value: *const Type, out: *[32]u8) !void {
            const chunks = try allocator.alloc([32]u8, (chunkCount(value) + 1) / 2 * 2);
            defer allocator.free(chunks);

            @memset(chunks, [_]u8{0} ** 32);

            _ = serializeIntoBytes(value, @ptrCast(chunks));

            try merkleize(@ptrCast(chunks), chunk_depth, out);
            mixInLength(value.items.len, out);
        }

        pub fn serializedSize(value: *const Type) usize {
            return value.items.len * Element.fixed_size;
        }

        pub fn serializeIntoBytes(value: *const Type, out: []u8) usize {
            @memcpy(out[0..value.items.len], value.items);
            return value.items.len;
        }

        pub fn deserializedLength(data: []const u8) !usize {
            if (data.len > limit) {
                return error.gtLimit;
            }
            return data.len;
        }

        pub fn validate(data: []const u8) !void {
            if (data.len > limit) {
                return error.gtLimit;
            }
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
            _ = try hexToBytes(out.items, hex_bytes);
        }
    };
}
