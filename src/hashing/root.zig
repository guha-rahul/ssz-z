const std = @import("std");
const depth = @import("depth.zig");
pub const GindexUint = depth.GindexUint;
pub const max_depth = depth.max_depth;
pub const Depth = depth.Depth;

const sha256 = @import("sha256.zig");
pub const hash = sha256.hash;
pub const hashOne = sha256.hashOne;

const zero_hash = @import("zero_hash.zig");
pub const getZeroHash = zero_hash.getZeroHash;

const merkleize_ = @import("merkleize.zig");
pub const merkleize = merkleize_.merkleize;
pub const mixInLength = merkleize_.mixInLength;
pub const maxChunksToDepth = merkleize_.maxChunksToDepth;

// Helpers for tests and higher-level callers
pub fn merkleizeBytes(allocator: std.mem.Allocator, out: *[32]u8, bytes: []const u8, chunk_size: usize) !void {
    _ = chunk_size; // chunk_size is fixed to 32 for SSZ
    const chunk_count: usize = (bytes.len + 31) / 32;
    const even_len: usize = ((chunk_count + 1) / 2) * 2;
    const depth_v = maxChunksToDepth(chunk_count);
    const chunks = try allocator.alloc([32]u8, even_len);
    defer allocator.free(chunks);
    @memset(chunks, [_]u8{0} ** 32);
    if (bytes.len > 0) {
        const flat: []u8 = @as([]u8, @ptrCast(chunks));
        @memcpy(flat[0..bytes.len], bytes);
    }
    const pairs_len = even_len / 2;
    const pairs: [][2][32]u8 = @as([*][2][32]u8, @ptrCast(chunks.ptr))[0..pairs_len];
    try merkleize(pairs, depth_v, out);
}

pub fn leafFromUint(value: u64) [32]u8 {
    var tmp: [32]u8 = [_]u8{0} ** 32;
    std.mem.writeInt(u64, tmp[0..8], value, .little);
    return tmp;
}

pub fn hashPair(out: *[32]u8, a: *const [32]u8, b: *const [32]u8) void {
    hashOne(out, a, b);
}
