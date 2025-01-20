const std = @import("std");
const TypeKind = @import("type_kind.zig").TypeKind;
const isFixedType = @import("type_kind.zig").isFixedType;

pub fn FixedContainerType(comptime ST: type) type {
    const ssz_fields = switch (@typeInfo(ST)) {
        .Struct => |s| s.fields,
        else => @compileError("Expected a struct type."),
    };

    comptime var native_fields: [ssz_fields.len]std.builtin.Type.StructField = undefined;
    comptime var _offsets: [ssz_fields.len]usize = undefined;
    comptime var _fixed_size: usize = 0;
    inline for (ssz_fields, 0..) |field, i| {
        if (!isFixedType(field.type)) {
            @compileError("FixedContainerType must only contain fixed fields");
        }

        native_fields[i] = .{
            .name = field.name,
            .type = field.type.Type,
            .default_value = null,
            .is_comptime = false,
            .alignment = @alignOf(field.type.Type),
        };
        _offsets[i] = _fixed_size;
        _fixed_size += field.type.fixed_size;
    }

    // this works for Zig 0.13
    // syntax in 0.14 or later could change, see https://github.com/ziglang/zig/issues/10710
    const T = @Type(.{
        .Struct = .{
            .layout = .auto,
            .backing_integer = null,
            .fields = native_fields[0..],
            // TODO: do we need to assign this value?
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });

    return struct {
        pub const kind = TypeKind.container;
        pub const Fields: type = ST;
        pub const fields: []const std.builtin.Type.StructField = ssz_fields;
        pub const Type: type = T;
        pub const fixed_size: usize = _fixed_size;
        pub const field_offsets: [fields.len]usize = _offsets;
        pub const chunk_count: usize = fields.len;

        pub fn serializeIntoBytes(value: *const Type, out: []u8) usize {
            var i: usize = 0;
            inline for (fields) |field| {
                const field_value = @field(value, field.name);
                i += field.type.serializeIntoBytes(&field_value, out[i..]);
            }
            return i;
        }

        pub fn deserializeFromBytes(data: []const u8, out: *Type) !void {
            var i: usize = 0;
            inline for (fields) |field| {
                try field.type.deserializeFromBytes(data[i .. i + field.type.fixed_size], &@field(out, field.name));
                i += field.type.fixed_size;
            }
        }

        pub fn validate(data: []const u8) !void {
            var i: usize = 0;
            inline for (fields) |field| {
                try field.type.validate(data[i .. i + field.type.fixed_size]);
                i += field.type.fixed_size;
            }
        }

        pub fn getFieldIndex(name: []const u8) usize {
            inline for (fields, 0..) |field, i| {
                if (std.mem.eql(u8, name, field.name)) {
                    return i;
                }
            } else {
                @compileError("field does not exist");
            }
        }
    };
}

pub fn VariableContainerType(comptime ST: type) type {
    const ssz_fields = switch (@typeInfo(ST)) {
        .Struct => |s| s.fields,
        else => @compileError("Expected a struct type."),
    };

    comptime var native_fields: [ssz_fields.len]std.builtin.Type.StructField = undefined;
    comptime var _offsets: [ssz_fields.len]usize = undefined;
    comptime var _min_size: usize = 0;
    comptime var _max_size: usize = 0;
    comptime var _fixed_end: usize = 0;
    comptime var _fixed_count: usize = 0;
    inline for (ssz_fields, 0..) |field, i| {
        _offsets[i] = _fixed_end;
        if (isFixedType(field.type)) {
            _min_size += field.type.fixed_size;
            _max_size += field.type.fixed_size;
            _fixed_end += field.type.fixed_size;
            _fixed_count += 1;
        } else {
            _min_size += field.type.min_size;
            _max_size += field.type.max_size;
            _fixed_end += 4;
        }

        native_fields[i] = .{
            .name = field.name,
            .type = field.type.Type,
            .default_value = null,
            .is_comptime = false,
            .alignment = @alignOf(field.type.Type),
        };
    }

    comptime {
        if (_fixed_count == ssz_fields.len) {
            @compileError("expected at least one fixed field type");
        }
    }

    const var_count = ssz_fields.len - _fixed_count;

    // this works for Zig 0.13
    // syntax in 0.14 or later could change, see https://github.com/ziglang/zig/issues/10710
    const T = @Type(.{
        .Struct = .{
            .layout = .auto,
            .backing_integer = null,
            .fields = native_fields[0..],
            // TODO: do we need to assign this value?
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });

    return struct {
        pub const kind = TypeKind.container;
        pub const fields: []const std.builtin.Type.StructField = ssz_fields;
        pub const Fields: type = ST;
        pub const Type: type = T;
        pub const min_size: usize = _min_size;
        pub const max_size: usize = _max_size;
        pub const field_offsets: [fields.len]usize = _offsets;
        pub const fixed_end: usize = _fixed_end;
        pub const fixed_count: usize = _fixed_count;
        pub const chunk_count: usize = fields.len;

        pub fn serializedSize(value: *const Type) usize {
            var i: usize = 0;
            inline for (fields) |field| {
                if (comptime isFixedType(field.type)) {
                    i += field.type.fixed_size;
                } else {
                    i += 4 + field.type.serializedSize(&@field(value, field.name));
                }
            }
            return i;
        }

        pub fn serializeIntoBytes(value: *const Type, out: []u8) usize {
            var fixed_index: usize = 0;
            var variable_index: usize = fixed_end;
            inline for (fields) |field| {
                if (comptime isFixedType(field.type)) {
                    // write field value
                    fixed_index += field.type.serializeIntoBytes(&@field(value, field.name), out[fixed_index..]);
                } else {
                    // write offset
                    std.mem.writeInt(u32, out[fixed_index..][0..4], @intCast(variable_index), .little);
                    fixed_index += 4;
                    // write field value
                    variable_index += field.type.serializeIntoBytes(&@field(value, field.name), out[variable_index..]);
                }
            }
            return variable_index;
        }

        pub fn deserializeFromBytes(data: []const u8, allocator: std.mem.Allocator, out: *Type) !void {
            if (data.len > max_size) {
                return error.InvalidSize;
            }

            const ranges = try readFieldRanges(data);

            inline for (fields, 0..) |field, i| {
                if (comptime isFixedType(field.type)) {
                    try field.type.deserializeFromBytes(
                        data[ranges[i][0]..ranges[i][1]],
                        &@field(out, field.name),
                    );
                } else {
                    try field.type.deserializeFromBytes(
                        data[ranges[i][0]..ranges[i][1]],
                        allocator,
                        &@field(out, field.name),
                    );
                }
            }
        }

        pub fn getFieldIndex(name: []const u8) usize {
            for (fields, 0..) |field, i| {
                if (std.mem.eql(u8, name, field.name)) {
                    return i;
                }
            } else {
                @compileError("field does not exist");
            }
        }

        pub const Serialized = struct {
            data: []const u8,

            const Self = @This();

            pub fn init(data: []const u8) !Serialized {
                // try validate(data);
                return .{ .data = data };
            }

            // pub fn deserialize(allocator: std.mem.Allocator, out: *Type) !void {}

            pub fn readField(self: Self, comptime name: []const u8) !fields[getFieldIndex(name)].type.Serialized {
                const ranges = try readFieldRanges(self.data);
                const field_index = getFieldIndex(name);
                return fields[field_index].type.Serialized{
                    .data = self.data[ranges[field_index][0]..ranges[field_index][1]],
                };
            }

            // pub fn readDescendent(self: Self, comptime path_str: []const u8) PathType(VariableContainerType(ST), path).Serialized {
            //     const ranges = try readFieldRanges(self.data);
            //     switch (comptime nextPathItem(VariableContainerType(ST), path_str)) {
            //         .last => |last| {
            //             const field_index = last.item_type.child.index;
            //             const range = ranges[field_index];
            //             return fields[field_index].type.Serialized{
            //                 .data = self.data[range[0]..range[1]],
            //             };
            //         },
            //         .not_last => |not_last| {
            //             const field_index = not_last.next.item_type.child.index;
            //             const range = ranges[field_index];
            //             const serialized_field = fields[field_index].type.Serialized{
            //                 .data = self.data[range[0]..range[1]],
            //             };
            //             serialized_field.readDescendent(not_last.rest_path_str);
            //         },
            //     }
            // }
        };

        // Returns the bytes ranges of all fields, both variable and fixed size.
        // Fields may not be contiguous in the serialized bytes, so the returned ranges are [start, end].
        pub fn readFieldRanges(data: []const u8) ![fields.len][2]usize {
            var ranges: [fields.len][2]usize = undefined;
            var offsets: [var_count + 1]u32 = undefined;
            try readVariableOffsets(data, &offsets);

            var fixed_index: usize = 0;
            var variable_index: usize = 0;
            inline for (fields, 0..) |field, i| {
                if (comptime isFixedType(field.type)) {
                    ranges[i] = [2]usize{ fixed_index, fixed_index + field.type.fixed_size };
                    fixed_index += field.type.fixed_size;
                } else {
                    ranges[i] = [2]usize{ offsets[variable_index], offsets[variable_index + 1] };
                    variable_index += 1;
                    fixed_index += 4;
                }
            }

            return ranges;
        }

        fn readVariableOffsets(data: []const u8, offsets: []u32) !void {
            var variable_index: usize = 0;
            var fixed_index: usize = 0;
            inline for (fields) |field| {
                if (comptime isFixedType(field.type)) {
                    fixed_index += field.type.fixed_size;
                } else {
                    const offset = std.mem.readInt(u32, data[fixed_index..][0..4], .little);
                    if (offset > data.len) {
                        return error.offsetOutOfRange;
                    }
                    if (variable_index == 0) {
                        if (offset != fixed_end) {
                            return error.offsetOutOfRange;
                        }
                    } else {
                        if (offset < offsets[variable_index - 1]) {
                            return error.offsetNotIncreasing;
                        }
                    }

                    offsets[variable_index] = offset;
                    variable_index += 1;
                    fixed_index += 4;
                }
            }
            // set 1 more at the end of the last variable field so that each variable field can consume 2 offsets
            offsets[variable_index] = @intCast(data.len);
        }

        pub fn validate(data: []const u8) !void {
            const ranges = try readFieldRanges(data);
            inline for (fields, 0..) |field, i| {
                const start = ranges[i][0];
                const end = ranges[i][1];
                if (comptime isFixedType(field.type)) {
                    const field_size = end - start;
                    if (field_size != field.type.fixed_size) {
                        return false;
                    }
                } else {
                    try field.type.validate(data[start..end]);
                }
            }
        }
    };
}

const UintType = @import("uint.zig").UintType;
const BoolType = @import("bool.zig").BoolType;
const ByteVectorType = @import("byte_vector.zig").ByteVectorType;
const FixedListType = @import("list.zig").FixedListType;

test "ContainerType - sanity" {
    // create a fixed container type and instance and round-trip serialize
    const Checkpoint = FixedContainerType(struct {
        slot: UintType(8),
        root: ByteVectorType(32),
    });

    var c: Checkpoint.Type = undefined;
    var c_buf: [Checkpoint.fixed_size]u8 = undefined;

    _ = Checkpoint.serializeIntoBytes(&c, &c_buf);
    try Checkpoint.deserializeFromBytes(&c_buf, &c);

    // create a variable container type and instance and round-trip serialize
    const allocator = std.testing.allocator;
    const Foo = VariableContainerType(struct {
        a: FixedListType(UintType(8), 32),
        b: FixedListType(UintType(8), 32),
        c: FixedListType(UintType(8), 32),
    });
    var f: Foo.Type = undefined;
    f.a = try std.ArrayListUnmanaged(u8).initCapacity(allocator, 10);
    f.b = try std.ArrayListUnmanaged(u8).initCapacity(allocator, 10);
    f.c = try std.ArrayListUnmanaged(u8).initCapacity(allocator, 10);
    defer f.a.deinit(allocator);
    defer f.b.deinit(allocator);
    defer f.c.deinit(allocator);
    f.a.expandToCapacity();
    f.b.expandToCapacity();
    f.c.expandToCapacity();

    const f_buf = try allocator.alloc(u8, Foo.serializedSize(&f));
    defer allocator.free(f_buf);
    _ = Foo.serializeIntoBytes(&f, f_buf);
    try Foo.deserializeFromBytes(f_buf, allocator, &f);
}
