const std = @import("std");
const TypeKind = @import("type_kind.zig").TypeKind;

pub fn BoolType() type {
    return struct {
        pub const kind = TypeKind.bool;
        pub const Type: type = bool;
        pub const fixed_size: usize = 1;

        pub const default_value: Type = false;

        pub fn hashTreeRoot(value: *const Type, out: *[32]u8) !void {
            @memset(out, 0);
            out[0] = if (value.*) 1 else 0;
        }

        pub fn serializeIntoBytes(value: *const Type, out: []u8) usize {
            const byte: u8 = if (value.*) 1 else 0;
            out[0] = byte;
            return 1;
        }

        pub fn deserializeFromBytes(data: []const u8, out: *Type) !void {
            if (data.len != 1) {
                return error.InvalidSize;
            }
            const byte = data[0];
            switch (byte) {
                0 => out.* = false,
                1 => out.* = true,
                else => return error.invalidBoolean,
            }
        }

        pub fn validate(data: []const u8) !void {
            if (data.len != 1) {
                return error.InvalidSize;
            }
            switch (data[0]) {
                0, 1 => {},
                else => return error.invalidBoolean,
            }
        }

        pub const serialized = struct {
            pub fn hashTreeRoot(data: []const u8, out: *[32]u8) !void {
                @memset(out, 0);
                @memcpy(out[0..fixed_size], data);
            }
        };

        pub fn deserializeFromJson(scanner: *std.json.Scanner, out: *Type) !void {
            switch (try scanner.next()) {
                .true => out.* = true,
                .false => out.* = false,
                else => return error.invalidJson,
            }
        }
    };
}
