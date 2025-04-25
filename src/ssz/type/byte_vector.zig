const std = @import("std");
const TypeKind = @import("type_kind.zig").TypeKind;
const UintType = @import("uint.zig").UintType;
const hexToBytes = @import("hex").hexToBytes;
const hexByteLen = @import("hex").hexByteLen;
const merkleize = @import("hashing").merkleize;
const maxChunksToDepth = @import("hashing").maxChunksToDepth;

pub fn isByteVectorType(ST: type) bool {
    return ST.kind == .vector and ST.Element.kind == .uint and ST.Element.fixed_size == 1 and ST == ByteVectorType(ST.length);
}

pub fn ByteVectorType(comptime _length: comptime_int) type {
    comptime {
        if (_length <= 0) {
            @compileError("length must be greater than 0");
        }
    }
    return struct {
        pub const kind = TypeKind.vector;
        pub const Element: type = UintType(8);
        pub const length: usize = _length;
        pub const Type: type = [length]Element.Type;
        pub const fixed_size: usize = Element.fixed_size * length;
        pub const chunk_count: usize = std.math.divCeil(usize, fixed_size, 32) catch unreachable;
        pub const chunk_depth: u8 = maxChunksToDepth(chunk_count);

        pub const default_value: Type = [_]Element.Type{Element.default_value} ** length;

        pub fn hashTreeRoot(value: *const Type, out: *[32]u8) !void {
            var chunks = [_][32]u8{[_]u8{0} ** 32} ** ((chunk_count + 1) / 2 * 2);
            _ = serializeIntoBytes(value, @ptrCast(&chunks));
            try merkleize(@ptrCast(&chunks), chunk_depth, out);
        }

        pub fn serializeIntoBytes(value: *const Type, out: []u8) usize {
            @memcpy(out[0..fixed_size], value);
            return length;
        }

        pub fn deserializeFromBytes(data: []const u8, out: *Type) !void {
            if (data.len != fixed_size) {
                return error.invalidLength;
            }

            @memcpy(out, data[0..fixed_size]);
        }

        pub const serialized = struct {
            pub fn validate(data: []const u8) !void {
                if (data.len != fixed_size) {
                    return error.invalidLength;
                }
            }

            pub fn hashTreeRoot(data: []const u8, out: *[32]u8) !void {
                var chunks = [_][32]u8{[_]u8{0} ** 32} ** ((chunk_count + 1) / 2 * 2);
                @memcpy(@as([]u8, @ptrCast(&chunks))[0..fixed_size], data);
                try merkleize(@ptrCast(&chunks), chunk_depth, out);
            }
        };

        pub fn deserializeFromJson(source: *std.json.Scanner, out: *Type) !void {
            const hex_bytes = switch (try source.next()) {
                .string => |v| v,
                else => return error.InvalidJson,
            };

            if (hexByteLen(hex_bytes) != length) {
                return error.InvalidJson;
            }
            _ = try hexToBytes(out, hex_bytes);
        }
    };
}
