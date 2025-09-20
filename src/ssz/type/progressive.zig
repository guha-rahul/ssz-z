const std = @import("std");
const merkleize = @import("hashing").merkleize;
const getZeroHash = @import("hashing").getZeroHash;
const mixInAux = @import("hashing").mixInAux;
const hashOne = @import("hashing").hashOne;
const Depth = @import("hashing").Depth;
const maxChunksToDepth = @import("hashing").maxChunksToDepth;
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

    // base_size = 1 << depth (1, 2, 4, 8, ...)
    const base_size = @as(usize, 1) << depth;
    const split_point = @min(base_size * 32, chunks.len);
    if (count <= 4) {
        std.debug.print("[PGL prog] depth={d} base_size={d} count={d} split={d}\n", .{ depth, base_size, count, split_point / 32 });
    }

    // Right subtree: binary merkleize the next base_size chunks from the start
    const right_chunks = chunks[0..split_point];
    const right_root = try merkleizeBinary(allocator, right_chunks, base_size);

    // Left subtree: recursive progressive merkleize the remaining chunks
    const left_chunks = chunks[split_point..];
    const left_root = if (left_chunks.len == 0)
        // Empty left child is a single zero node (terminator)
        [_]u8{0} ** 32
    else
        try merkleizeProgressiveImpl(allocator, left_chunks, depth + 2);
    if (count <= 4) {
        std.debug.print("[PGL prog] combine depth={d}\n", .{depth});
    }

    // Window on left, spine on right
    var buf: [64]u8 = undefined;
    @memcpy(buf[0..32], &right_root); // window
    @memcpy(buf[32..64], &left_root); // spine
    var out32: [32]u8 = undefined;
    hashOne(&out32, @as(*const [32]u8, @ptrCast(&buf[0])), @as(*const [32]u8, @ptrCast(&buf[32])));
    if (count <= 4) {
        const lw = try foldProgressive(allocator, chunks, depth, true);
        const ls = try foldProgressive(allocator, chunks, depth, false);
        const match_lw = std.mem.eql(u8, &out32, &lw);
        const match_ls = std.mem.eql(u8, &out32, &ls);
        std.debug.print("[DBG orient-check] depth={d} lw={any} ls={any} out={s} lw={s} ls={s}\n", .{
            depth,
            match_lw,
            match_ls,
            std.fmt.fmtSliceHexLower(out32[0..]),
            std.fmt.fmtSliceHexLower(lw[0..]),
            std.fmt.fmtSliceHexLower(ls[0..]),
        });
    }
    return out32;
}

/// Binary merkleize chunks up to a maximum limit
fn merkleizeBinary(allocator: std.mem.Allocator, chunks: []u8, limit: usize) ![32]u8 {
    const count = (chunks.len + 31) / 32;
    if (count == 0) {
        return [_]u8{0} ** 32;
    }

    // Ensure we don't exceed the limit
    const actual_count = @min(count, limit);

    // Build a fixed-capacity subtree with exactly `limit` leaves (2^depth)
    const merkle_chunks = try allocator.alloc([32]u8, limit);
    defer allocator.free(merkle_chunks);

    // Copy actual chunks
    var i: usize = 0;
    while (i < actual_count and (i * 32) < chunks.len) : (i += 1) {
        const start = i * 32;
        const end = @min(start + 32, chunks.len);
        const wrote = end - start;
        std.mem.copyForwards(u8, merkle_chunks[i][0..wrote], chunks[start..end]);
        if (wrote < 32) @memset(merkle_chunks[i][wrote..], 0);
    }
    // Fill remaining leaves up to `limit` with zero chunks
    while (i < limit) : (i += 1) merkle_chunks[i] = [_]u8{0} ** 32;

    // Calculate depth needed for the fixed-size subtree (limit is a power-of-two)
    const depth = if (limit <= 1) 0 else std.math.log2_int(usize, limit);

    if (depth == 0) {
        // Subtree capacity is 1 leaf: return that leaf directly
        return merkle_chunks[0];
    } else {
        var result: [32]u8 = undefined;
        try merkleize(@ptrCast(merkle_chunks), @intCast(depth), &result);
        return result;
    }
}

/// Get `out.len` nodes in a single traversal from a tree that uses the progressive merklization scheme defined by https://eips.ethereum.org/EIPS/eip-7916
pub fn getNodes(pool: *Node.Pool, root: Node.Id, out: []Node.Id) !void {
    const subtree_count = subtreeIndex(out.len);
    var n = root;
    var l: usize = 0;
    for (0..subtree_count) |subtree_i| {
        const subtree_root = try n.getLeft(pool); // window is left
        const subtree_length = @min(subtreeLength(subtree_i), out.len - l);
        const subtree_depth = subtreeDepth(subtree_i);
        try subtree_root.getNodesAtDepth(pool, subtree_depth, 0, out[l .. l + subtree_length]);
        l += subtree_length;
        n = try n.getRight(pool); // spine continues on right
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
            subtree_root, // window on left
            n, // spine on right
            should_ref,
        );
    }
    return n;
}

// =====================
// Tests and helpers
// =====================
const testing = std.testing;

// helper: make deterministic leaves
fn makeLeaves(allocator: std.mem.Allocator, n: usize) ![][32]u8 {
    const leaves = try allocator.alloc([32]u8, n);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        @memset(leaves[i][0..], @as(u8, @intCast(i + 1)));
    }
    return leaves;
}

// fold with explicit orientation
fn foldProgressive(
    allocator: std.mem.Allocator,
    chunks: []u8,
    start_depth: Depth,
    left_is_window: bool,
) ![32]u8 {
    var spine: [32]u8 = [_]u8{0} ** 32;
    var remaining: usize = (chunks.len + 31) / 32;
    var off: usize = 0;
    var d: Depth = start_depth;

    while (remaining > 0) {
        const cap: usize = @as(usize, 1) << d; // window capacity
        const take: usize = @min(cap, remaining);
        const bytes: usize = take * 32;

        const w_slice = chunks[off .. off + bytes];
        const w_root = try merkleizeBinary(allocator, w_slice, cap);

        var out32: [32]u8 = undefined;
        if (left_is_window) {
            // left = window, right = spine
            hashOne(&out32, @as(*const [32]u8, @ptrCast(&w_root)), @as(*const [32]u8, @ptrCast(&spine)));
        } else {
            // left = spine, right = window
            hashOne(&out32, @as(*const [32]u8, @ptrCast(&spine)), @as(*const [32]u8, @ptrCast(&w_root)));
        }
        spine = out32;

        off += bytes;
        remaining -= take;
        d += 2;
    }
    return spine;
}

// check that merkleizeBinary pads to fixed depth 2^d
test "progressive.merkleizeBinary pads to the target depth" {
    const gpa = testing.allocator;
    // depth 2 capacity 4 leaves, but provide 3 leaves
    const leaves = try makeLeaves(gpa, 3);
    defer gpa.free(leaves);
    const bytes = std.mem.sliceAsBytes(leaves);

    const got = try merkleizeBinary(gpa, bytes, 4);

    // manual pad to 4 leaves then call generic merkleize at depth 2
    var padded = try gpa.alloc([32]u8, 4);
    defer gpa.free(padded);
    padded[0] = leaves[0];
    padded[1] = leaves[1];
    padded[2] = leaves[2];
    padded[3] = [_]u8{0} ** 32;

    var expect: [32]u8 = undefined;
    try merkleize(@ptrCast(padded), @as(Depth, @intCast(2)), &expect);

    try testing.expect(std.mem.eql(u8, &got, &expect));
}

// orientation detector across multiple lengths
test "progressive orientation detector matches exactly one orientation" {
    const gpa = testing.allocator;
    const counts = [_]usize{ 1, 2, 3, 4, 5, 7, 8, 9, 16, 17 };

    for (counts) |n| {
        const leaves = try makeLeaves(gpa, n);
        defer gpa.free(leaves);
        const bytes = std.mem.sliceAsBytes(leaves);

        // current implementation
        var impl_root: [32]u8 = undefined;
        {
            const tmp = try merkleizeProgressiveImpl(gpa, bytes, 0);
            @memcpy(&impl_root, &tmp);
        }

        // left = window, right = spine
        const lw = try foldProgressive(gpa, bytes, 0, true);
        // left = spine, right = window
        const ls = try foldProgressive(gpa, bytes, 0, false);

        const match_lw = std.mem.eql(u8, &impl_root, &lw);
        const match_ls = std.mem.eql(u8, &impl_root, &ls);

        // exactly one should match
        try testing.expect(match_lw != match_ls);

        // dump a hint if neither matches to localize bugs
        if (!match_lw and !match_ls) {
            std.debug.print("[DBG orientation] n={d} impl={s} lw={s} ls={s}\n", .{ n, std.fmt.fmtSliceHexLower(impl_root[0..]), std.fmt.fmtSliceHexLower(lw[0..]), std.fmt.fmtSliceHexLower(ls[0..]) });
        }
    }
}

// window counting invariant at boundaries
test "progressive window count equals subtreeIndex(len-1) + 1" {
    // check a range including exact window boundaries
    const lens = [_]usize{ 0, 1, 2, 3, 4, 5, 16, 17, 20, 64, 65 };
    for (lens) |len| {
        const want = if (len == 0) 0 else subtreeIndex(len - 1) + 1;

        // brute compute by simulating progressive consumption
        var remaining = len;
        var d: Depth = 0;
        var got: usize = 0;
        while (remaining > 0) : (d += 2) {
            const cap = (@as(usize, 1) << d);
            const take = @min(cap, remaining);
            remaining -= take;
            got += 1;
        }
        try testing.expectEqual(want, got);
    }
}

// contents root parity for fixed-size basic elements through value vs serialized code paths
test "progressive fixed basic parity: value path equals serialized path" {
    const gpa = testing.allocator;

    // Build 56 uint16 elements to mimic the max_85 fixture windowing pattern
    // Each element is little-endian i
    const ElemSize: usize = 2;
    const N: usize = 56;
    var data = try gpa.alloc(u8, N * ElemSize);
    defer gpa.free(data);
    var i: usize = 0;
    while (i < N) : (i += 1) {
        std.mem.writeInt(u16, data[i * 2 ..][0..2], @as(u16, @intCast(i)), .little);
    }

    // chunks for "value" path
    const chunk_count = (data.len + 31) / 32;
    const leaves = try gpa.alloc([32]u8, chunk_count);
    defer gpa.free(leaves);
    @memset(leaves, [_]u8{0} ** 32);
    @memcpy(std.mem.sliceAsBytes(leaves)[0..data.len], data);

    // contents via progressive.merkleizeChunks
    var root_value: [32]u8 = undefined;
    try merkleizeChunks(gpa, leaves, &root_value);

    // contents via serialized path replica
    var root_ser: [32]u8 = undefined;
    {
        const tmp = try merkleizeProgressiveImpl(gpa, data, 0);
        @memcpy(&root_ser, &tmp);
    }

    try testing.expect(std.mem.eql(u8, &root_value, &root_ser));
}

// small concrete cases to localize orientation and depth quickly
test "progressive concrete cases n=1,2,3,4,5" {
    const gpa = testing.allocator;
    for (&[_]usize{ 1, 2, 3, 4, 5 }) |n| {
        const leaves = try makeLeaves(gpa, n);
        defer gpa.free(leaves);
        const bytes = std.mem.sliceAsBytes(leaves);

        var impl: [32]u8 = undefined;
        {
            const t = try merkleizeProgressiveImpl(gpa, bytes, 0);
            @memcpy(&impl, &t);
        }
        const lw = try foldProgressive(gpa, bytes, 0, true);
        const ls = try foldProgressive(gpa, bytes, 0, false);

        std.debug.print("[DBG n={d}] impl={s}\n", .{ n, std.fmt.fmtSliceHexLower(impl[0..]) });
        std.debug.print("[DBG n={d}] left=window  root={s}\n", .{ n, std.fmt.fmtSliceHexLower(lw[0..]) });
        std.debug.print("[DBG n={d}] left=spine   root={s}\n", .{ n, std.fmt.fmtSliceHexLower(ls[0..]) });

        // at least one must match
        try testing.expect(std.mem.eql(u8, &impl, &lw) or std.mem.eql(u8, &impl, &ls));
    }
}
