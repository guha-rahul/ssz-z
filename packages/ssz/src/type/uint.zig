const std = @import("std");
const TypeKind = @import("type_kind.zig").TypeKind;
const native_endian = @import("builtin").cpu.arch.endian();

pub fn UintType(comptime bits: comptime_int) type {
    const NativeType = switch (bits) {
        8 => u8,
        16 => u16,
        32 => u32,
        64 => u64,
        128 => u128,
        256 => u256,
        else => @compileError("bits must be 8, 16, 32, 64, 128, 256"),
    };
    const bytes = bits / 8;
    return struct {
        pub const kind = TypeKind.uint;
        pub const Type: type = NativeType;
        pub const fixed_size: usize = bytes;

        pub fn serializeIntoBytes(value: *const Type, out: []u8) usize {
            std.mem.writeInt(Type, out[0..bytes], value.*, .little);
            return bytes;
        }

        pub fn deserializeFromBytes(data: []const u8, out: *Type) !void {
            if (data.len != fixed_size) {
                return error.InvalidSize;
            }

            out.* = std.mem.readInt(Type, data[0..bytes], .little);
        }

        pub fn validate(data: []const u8) !void {
            if (data.len != fixed_size) {
                return error.InvalidSize;
            }
        }

        pub fn deserializeFromJson(scanner: *std.json.Scanner, out: *Type) !void {
            try switch (try scanner.next()) {
                .string => |v| {
                    out.* = try std.fmt.parseInt(Type, v, 10);
                },
                else => error.invalidJson,
            };
        }
    };
}

test "UintType - sanity" {
    const Uint8 = UintType(8);

    var u: Uint8.Type = undefined;
    var u_buf: [Uint8.fixed_size]u8 = undefined;
    _ = Uint8.serializeIntoBytes(&u, &u_buf);
    try Uint8.deserializeFromBytes(&u_buf, &u);

    const allocator = std.testing.allocator;
    var json = std.json.Scanner.initCompleteInput(
        allocator,
        "\"255\"",
    );
    defer json.deinit();
    try Uint8.deserializeFromJson(&json, &u);
}
