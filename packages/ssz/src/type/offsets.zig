const std = @import("std");
const isFixedType = @import("type_kind.zig").isFixedType;

/// helper to read offsets from serialized arrays
pub fn Offsets(comptime ST: type) type {
    comptime {
        if (ST.kind != .vector and ST.kind != .list) {
            @compileError("ST must be a vector or list");
        }
        if (isFixedType(ST.Element)) {
            @compileError("ST.Element must not be a fixed type");
        }
    }
    return struct {
        pub fn firstOffset(data: []const u8) !u32 {
            const first_offset = std.mem.readInt(u32, data[0..4], .little);

            if (first_offset == 0) {
                return error.zeroOffset;
            }

            if (first_offset % 4 != 0) {
                return error.offsetNotDivisibleBy4;
            }

            return first_offset;
        }

        pub fn readVariableOffsets(data: []const u8, first_offset: u32, offsets: []u32) !void {
            // A variable-sized array has a contiguous section of offsets, then the data
            //
            //    [offset 1] [offset 2] [data 1 ..........] [data 2 ..]
            // 0x 08000000   0e000000   010002000300        01000200
            //
            // Ensure that:
            // - Offsets point to regions of > 0 bytes, i.e. are increasing
            // - Offsets don't point to bytes outside of the array's size
            //
            // In the example above the first offset is 8, so 8 / 4 = 2 offsets.
            // Then, read the rest of offsets to get offsets = [8, 14]
            offsets[0] = first_offset;
            // a final offset, the total data length is appended
            // so that offsets can be consumed in (i, i+1) pairs
            offsets[offsets.len - 1] = @intCast(data.len);

            for (offsets[1 .. offsets.len - 1], 1..) |*offset, i| {
                const off = std.mem.readInt(u32, data[i * 4 ..][0..4], .little);
                if (off > data.len) {
                    return error.offsetOutOfRange;
                }
                const prev_offset = offsets[i - 1];
                if (off < prev_offset) {
                    return error.offsetNotIncreasing;
                }
                offset.* = off;
            }
        }
    };
}

/// Iterate over variable offsets, also doing validation
/// A variable-sized array has a contiguous section of offsets, then the data
///
///    [offset 1] [offset 2] [data 1 ..........] [data 2 ..]
/// 0x 08000000   0e000000   010002000300        01000200
///
/// Ensure that:
/// - Offsets point to regions of > 0 bytes, i.e. are increasing
/// - Offsets don't point to bytes outside of the array's size
///
/// In the example above the first offset is 8, so 8 / 4 = 2 offsets.
/// Then, read the rest of offsets to get offsets = [8, 14]
pub fn OffsetIterator(comptime ST: type) type {
    comptime {
        if (ST.kind != .vector and ST.kind != .list) {
            @compileError("ST must be a vector or list");
        }
        if (isFixedType(ST.Element)) {
            @compileError("ST.Element must not be a fixed type");
        }
    }
    return struct {
        data: []const u8,
        prev_offset: u32,
        pos: u32,

        const Self = @This();

        pub fn init(data: []const u8) Self {
            return Self{ .data = data, .prev_offset = 0, .pos = 0 };
        }

        pub fn firstOffset(self: Self) !u32 {
            const first_offset = std.mem.readInt(u32, self.data[0..4], .little);

            if (first_offset == 0) {
                return error.zeroOffset;
            }

            if (first_offset % 4 != 0) {
                return error.offsetNotDivisibleBy4;
            }

            const offset_count: usize = first_offset / 4;
            if (ST.kind == .vector) {
                if (offset_count != ST.length) {
                    return error.invalidOffsetCount;
                }
            }
            if (ST.kind == .list) {
                if (offset_count > ST.limit) {
                    return error.invalidOffsetCount;
                }
            }

            return first_offset;
        }

        pub fn readOffset(self: Self, i: usize) u32 {
            std.mem.readInt(u32, self.data[i * 4 ..][0..4], .little);
        }

        pub fn next(self: *Self) !u32 {
            const offset = if (self.pos == 0)
                try self.firstOffset()
            else
                self.readOffset(self.pos);

            if (offset > self.data.len) {
                return error.offsetOutOfRange;
            }
            if (offset < self.prev_offset) {
                return error.offsetNotIncreasing;
            }

            self.pos += 1;
            self.prev_offset = offset;

            return offset;
        }
    };
}
