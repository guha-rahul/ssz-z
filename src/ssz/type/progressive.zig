const std = @import("std");
const merkleize = @import("hashing").merkleize;
const mixInAux = @import("hashing").mixInAux;
const hashOne = @import("hashing").hashOne;
const Depth = @import("hashing").Depth;
const Node = @import("persistent_merkle_tree").Node;
const Gindex = @import("persistent_merkle_tree").Gindex;

const base_count = 1;
const scaling_factor = 4;

// Given a chunk index, return the gindex based on the progressive merklization scheme defined by https://eips.ethereum.org/EIPS/eip-7916
pub fn chunkGindex(chunk_i: usize) Gindex {
    const subtree_i = subtreeIndex(chunk_i);
    var i = subtree_i;
    var gindex: Gindex.Uint = 1;
    var subtree_starting_index = 0;
    // navigate down to the successor root at chunk_i
    // also track the starting index at that level's subtree
    while (i > 0) {
        i -= 1;
        gindex *= 2;
        subtree_starting_index += subtreeLength(i);
    }

    // navigate to that level's subtree
    gindex += 1;

    // navigate to the subtree starting leaf
    gindex *= try std.math.powi(usize, 2, subtreeDepth(subtree_i));

    // navigate to the chunk index within the subtree
    gindex += chunk_i - subtree_starting_index;
    return @enumFromInt(gindex);
}

pub fn subtreeIndex(chunk_i: usize) usize {
    var left: usize = chunk_i;
    var subtree_length: usize = base_count;
    var subtree_i: usize = 0;
    while (left > 0) {
        left -|= subtree_length;
        subtree_length *= scaling_factor;
        subtree_i += 1;
    }
    return subtree_i;
}

pub fn subtreeLength(subtree_i: usize) usize {
    return std.math.pow(usize, scaling_factor, subtree_i);
}

pub fn subtreeDepth(subtree_i: usize) Depth {
    return @intCast(subtree_i * std.math.log2_int(usize, scaling_factor));
}

/// merkleize chunks using the progressive merklization scheme defined by https://eips.ethereum.org/EIPS/eip-7916
/// Implementation follows the subtree_fill_progressive algorithm from the Go reference
pub fn merkleizeChunks(allocator: std.mem.Allocator, chunks: [][32]u8, out: *[32]u8) !void {
    if (chunks.len == 0) {
        out.* = [_]u8{0} ** 32;
        return;
    }

    // Convert chunks to byte slice for the recursive algorithm
    const chunk_bytes = std.mem.sliceAsBytes(chunks);
    const result = try merkleizeProgressiveImpl(allocator, chunk_bytes, 0);
    @memcpy(&out.*, &result);
}

/// Recursive progressive merklization following subtree_fill_progressive
fn merkleizeProgressiveImpl(allocator: std.mem.Allocator, chunks: []u8, depth: Depth) ![32]u8 {
    const count = (chunks.len + 31) / 32; // number of 32-byte chunks

    if (count == 0) {
        return [_]u8{0} ** 32;
    }

    // base_size = 1 << depth (1, 4, 16, 64, 256...)
    const base_size = @as(usize, 1) << depth;
    const split_point = @min(base_size * 32, chunks.len);

    // Right subtree: binary merkleize first base_size chunks
    const right_chunks = chunks[0..split_point];
    const right_root = try merkleizeBinary(allocator, right_chunks, base_size);

    // Left subtree: recursive progressive merkleize remaining chunks
    const left_chunks = chunks[split_point..];
    const left_root = if (left_chunks.len == 0)
        [_]u8{0} ** 32
    else
        try merkleizeProgressiveImpl(allocator, left_chunks, depth + 2);

    // Hash left and right together
    var combined: [64]u8 = undefined;
    @memcpy(combined[0..32], &left_root);
    @memcpy(combined[32..64], &right_root);
    var result: [32]u8 = undefined;
    hashOne(&result, @as(*const [32]u8, @ptrCast(&combined[0])), @as(*const [32]u8, @ptrCast(&combined[32])));
    return result;
}

/// Binary merkleize chunks up to a maximum limit
fn merkleizeBinary(allocator: std.mem.Allocator, chunks: []u8, limit: usize) ![32]u8 {
    const count = (chunks.len + 31) / 32;
    if (count == 0) {
        return [_]u8{0} ** 32;
    }

    // Ensure we don't exceed the limit
    const actual_count = @min(count, limit);

    // Pad to even number for merkleization
    const even_count = if (actual_count % 2 == 1) actual_count + 1 else actual_count;
    const merkle_chunks = try allocator.alloc([32]u8, even_count);
    defer allocator.free(merkle_chunks);

    // Copy actual chunks
    var i: usize = 0;
    while (i < actual_count and (i * 32) < chunks.len) : (i += 1) {
        const start = i * 32;
        const end = @min(start + 32, chunks.len);
        @memcpy(&merkle_chunks[i], chunks[start..end]);
        // Pad with zeros if needed
        if (end - start < 32) {
            @memset(merkle_chunks[i][end - start ..], 0);
        }
    }

    // Fill remaining with zeros
    while (i < even_count) : (i += 1) {
        merkle_chunks[i] = [_]u8{0} ** 32;
    }

    // Calculate depth needed
    const depth = if (even_count <= 1) 0 else std.math.log2_int_ceil(usize, even_count);

    var result: [32]u8 = undefined;
    try merkleize(@ptrCast(merkle_chunks), @intCast(depth), &result);
    return result;
}

/// Get `out.len` nodes in a single traversal from a tree that uses the progressive merklization scheme defined by https://eips.ethereum.org/EIPS/eip-7916
pub fn getNodes(pool: *Node.Pool, root: Node.Id, out: []Node.Id) !void {
    const subtree_count = subtreeIndex(out.len);
    var n = root;
    var l: usize = 0;
    for (0..subtree_count) |subtree_i| {
        const subtree_root = try n.getLeft(pool);
        const subtree_length = @min(subtreeLength(subtree_i), out.len - l);
        const subtree_depth = subtreeDepth(subtree_i);
        try subtree_root.getNodesAtDepth(pool, subtree_depth, 0, out[l .. l + subtree_length]);
        l += subtree_length;
        n = try n.getRight(pool);
    }
    if (!std.mem.eql(u8, &n.getRoot(pool).*, &[_]u8{0} ** 32)) {
        return error.InvalidTerminatorNode;
    }
}

pub fn fillWithContents(pool: *Node.Pool, nodes: []Node.Id, should_ref: bool) !Node.Id {
    const subtree_count = subtreeIndex(nodes.len);
    var l: usize = 0;
    var n: Node.Id = @enumFromInt(0);
    for (0..subtree_count) |subtree_i| {
        const subtree_depth = subtreeDepth(subtree_i);
        const subtree_length = @min(subtreeLength(subtree_i), nodes.len - l);
        const subtree_root = try Node.fillWithContents(pool, nodes[l .. l + subtree_length], subtree_depth, false);
        l += subtree_length;
        n = try pool.createBranch(
            subtree_root,
            n,
            should_ref,
        );
    }
    return n;
}
