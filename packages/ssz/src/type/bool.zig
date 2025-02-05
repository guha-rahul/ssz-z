const std = @import("std");
const TypeKind = @import("type_kind.zig").TypeKind;

pub fn BoolType() type {
    return struct {
        pub const kind = TypeKind.bool;
        pub const Type: type = bool;
        pub const fixed_size: usize = 1;

        pub fn serializeIntoBytes(value: *const Type, out: []u8) usize {
            const byte: u8 = if (value.*) 1 else 0;
            out[0] = byte;
            return 1;
        }

        pub fn deserializeFromBytes(data: []const u8, out: *Type) !void {
            const byte = data[0];
            switch (byte) {
                0 => out.* = false,
                1 => out.* = true,
                else => return error.invalidBoolean,
            }
        }

        pub fn validate(data: []const u8) !void {
            if (data.len != 1) {
                return error.InvalidLength;
            }
            switch (data[0]) {
                0, 1 => {},
                else => return error.invalidBoolean,
            }
        }

        pub fn deserializeFromJson(scanner: *std.json.Scanner, out: *Type) !void {
            switch (try scanner.next()) {
                .true => out.* = true,
                .false => out.* = false,
                else => return error.invalidJson,
            }
        }
    };
}
