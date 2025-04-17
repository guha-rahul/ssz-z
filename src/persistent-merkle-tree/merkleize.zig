const std = @import("std");
const zh = @import("zero_hash.zig");
const HashError = @import("hash_fn.zig").HashError;
const HashFn = @import("hash_fn.zig").HashFn;
const sha256Hash = @import("sha256.zig").sha256Hash;
const digest64Into = @import("sha256.zig").digest64Into;

pub fn merkleize(chunks: [][32]u8, chunk_count: usize, out: *[32]u8) !void {
    if (chunk_count == 0) {
        return error.InvalidInput;
    }

    if (chunks.len == 1 and chunk_count == 1) {
        @memcpy(out, &chunks[0]);
        return;
    }
    const bit_len: usize = @sizeOf(usize) * 8 - @clz(chunk_count - 1);
    const layer_count: usize = @sizeOf(usize) * 8 - @clz(std.math.pow(usize, 2, bit_len) - 1);

    // std.debug.print("chunk_count: {} bit_len: {} layer_count: {}\n", .{ chunk_count, bit_len, layer_count });

    if (chunks.len == 0) {
        @memcpy(out, try zh.getZeroHash(layer_count));
        return;
    }

    if (chunks.len % 2 != 0) {
        return error.InvalidInput;
    }

    // hash into the same buffer
    var buf = chunks;
    for (0..layer_count) |i| {
        if (buf.len % 2 == 1) {
            buf.len += 1;
            @memcpy(&buf[buf.len - 1], try zh.getZeroHash(i));
        }

        const buf_out = buf[0 .. buf.len / 2];
        try sha256Hash(buf, buf_out);

        buf = buf_out;
    }

    std.mem.copyForwards(u8, out, &buf[0]);
}

/// Given maxChunkCount return the chunkDepth
/// ```
/// n: [0,1,2,3,4,5,6,7,8,9]
/// d: [0,0,1,2,2,3,3,3,3,4]
/// ```
pub fn maxChunksToDepth(n: usize) usize {
    if (n == 0) return 0;

    // Compute log2(n) and ceil it
    const temp_f64: f64 = @floatFromInt(n);
    const chunk_f64 = std.math.log2(temp_f64);
    const result = std.math.ceil(chunk_f64);
    return @intFromFloat(result);
}

pub fn mixInLength(len: u256, out: *[32]u8) void {
    var tmp: [32]u8 = undefined;
    std.mem.writeInt(u256, &tmp, len, .little);
    digest64Into(out, &tmp, out);
}

const rootToHex = @import("hex").rootToHex;
test "merkleize" {
    const TestCase = struct {
        chunk_count: usize,
        expected: []const u8,
    };

    // TODO: fix commented cases
    const test_cases = comptime [_]TestCase{
        TestCase{ .chunk_count = 0, .expected = "0x0000000000000000000000000000000000000000000000000000000000000000" },
        TestCase{ .chunk_count = 1, .expected = "0x0000000000000000000000000000000000000000000000000000000000000000" },
        TestCase{ .chunk_count = 2, .expected = "0x5c85955f709283ecce2b74f1b1552918819f390911816e7bb466805a38ab87f3" },
        TestCase{ .chunk_count = 3, .expected = "0xee9bc4a60987257d8d2027f6352b676c86ed3c246622b135436eb69314974c7c" },
        TestCase{ .chunk_count = 4, .expected = "0xd35f51699389da7eec7ce5eb02640c6d318cf51ae39eca890bbc7b84ecb5da68" },
        TestCase{ .chunk_count = 5, .expected = "0x26b864a5fd6483296b66858580164a884e7ba8797ebf4c4a2500843b354f438d" },
        TestCase{ .chunk_count = 6, .expected = "0xcc5c078ca453a6a13bfa84c18f111ccb77477bd6284988fc9e414691cdba276d" },
        TestCase{ .chunk_count = 7, .expected = "0x51778544b05e4255d74b710bae7b966a5e5e7a00e3311bcb1a4059053bf9ce01" },
        TestCase{ .chunk_count = 8, .expected = "0x5837f89a763ab800bd3b8de6562aadb4e7ba54da125d1f41a7ebdcdebc977883" },
    };

    inline for (test_cases) |tc| {
        const chunk_count = if (tc.chunk_count % 2 == 1 and tc.chunk_count != 1) tc.chunk_count + 1 else tc.chunk_count;
        const total_chunk_count = if (tc.chunk_count == 0) 1 else tc.chunk_count;

        const expected = tc.expected;
        var chunks = [_][32]u8{[_]u8{0} ** 32} ** chunk_count;
        for (&chunks, 0..) |*chunk, i| {
            if (i >= tc.chunk_count) break;
            for (chunk) |*b| {
                b.* = @intCast(i);
            }
        }

        var output: [32]u8 = undefined;
        try merkleize(&chunks, total_chunk_count, &output);
        const hex = try rootToHex(&output);
        try std.testing.expectEqualSlices(u8, expected, &hex);
    }
}

test "maxChunksToDepth" {
    const results = [_]usize{ 0, 0, 1, 2, 2, 3, 3, 3, 3, 4 };
    for (0..results.len) |i| {
        const expected = results[i];
        const actual = maxChunksToDepth(i);
        try std.testing.expectEqual(expected, actual);
    }
}
