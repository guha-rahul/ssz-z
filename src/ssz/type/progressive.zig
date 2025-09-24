const std = @import("std");
const merkleize = @import("hashing").merkleize;
const mixInAux = @import("hashing").mixInAux;
const hashOne = @import("hashing").hashOne;
const Depth = @import("hashing").Depth;
const Node = @import("persistent_merkle_tree").Node;
const Gindex = @import("persistent_merkle_tree").Gindex;

pub const std_options = .{ .log_level = .debug };
pub const log_scope_levels = &.{.{ .scope = .pgl, .level = .debug }};
const log = std.log.scoped(.pgl);

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
pub fn merkleizeChunks(allocator: std.mem.Allocator, chunks: [][32]u8, out: *[32]u8) !void {
    // Handle empty chunks case
    if (chunks.len == 0) {
        out.* = [_]u8{0} ** 32;
        return;
    }

    const subtree_count = subtreeIndex(chunks.len);
    const subtree_roots = try allocator.alloc([32]u8, subtree_count);
    defer allocator.free(subtree_roots);

    var c = chunks;
    var subtree_length: usize = base_count;
    for (0..subtree_count) |subtree_i| {
        if (c.len <= subtree_length) {
            const final_subtree_chunks = try allocator.alloc([32]u8, subtree_length);
            defer allocator.free(final_subtree_chunks);

            @memcpy(final_subtree_chunks[0..c.len], c);
            @memset(final_subtree_chunks[c.len..], [_]u8{0} ** 32);

            const depth = subtreeDepth(subtree_i);
            if (depth == 0) {
                // Single chunk: use directly, no merkleize
                subtree_roots[subtree_i] = final_subtree_chunks[0];
            } else {
                // Multiple chunks: binary merkleize
                try merkleize(@ptrCast(final_subtree_chunks), depth, &subtree_roots[subtree_i]);
            }
        } else {
            const depth = subtreeDepth(subtree_i);
            if (depth == 0) {
                // Single chunk: use directly, no merkleize
                subtree_roots[subtree_i] = c[0];
            } else {
                // Multiple chunks: binary merkleize
                try merkleize(@ptrCast(c[0..subtree_length]), depth, &subtree_roots[subtree_i]);
            }

            c = c[subtree_length..];
            subtree_length *= scaling_factor;
        }
    }
    out.* = [_]u8{0} ** 32;
    var subtree_i = subtree_count;
    while (subtree_i > 0) {
        subtree_i -= 1;
        hashOne(
            out,
            out,
            &subtree_roots[subtree_i],
        );
    }
}

/// Get `out.len` nodes in a single traversal from a tree that uses the progressive merklization scheme defined by https://eips.ethereum.org/EIPS/eip-7916
pub fn getNodes(pool: *Node.Pool, root: Node.Id, out: []Node.Id) !void {
    const subtree_count = subtreeIndex(out.len);

    // std.debug.print("=== getNodes CALLED ===\n", .{});
    // std.debug.print("root: {}, hash: {}\n", .{ root, std.fmt.fmtSliceHexLower(root.getRoot(pool)) });
    // std.debug.print("out.len={}, subtree_count={}\n", .{ out.len, subtree_count });

    errdefer {
        // log.debug("=== getNodes FAILED ===", .{});
        // log.debug("out.len={}, subtree_count={}", .{ out.len, subtreeIndex(out.len) });
        // log.debug("root hash: {}", .{std.fmt.fmtSliceHexLower(root.getRoot(pool))});
    }

    // Start directly from root (the contents node/progressive structure root)
    // The root parameter IS the contents node we need to traverse
    var n = root;
    // std.debug.print("Starting from contents node: {}, hash: {}\n", .{ n, std.fmt.fmtSliceHexLower(n.getRoot(pool)) });

    // Zero intermediate nodes are normal padding in progressive trees, not indicators of empty data
    // Always proceed with normal progressive traversal logic
    // std.debug.print("Proceeding with normal progressive traversal\n", .{});

    errdefer {
        // log.debug("contents (root.left) hash: {}", .{std.fmt.fmtSliceHexLower(n.getRoot(pool))});
        // const length_node = root.getRight(pool) catch @as(Node.Id, @enumFromInt(0));
        // log.debug("length (root.right) hash: {}", .{std.fmt.fmtSliceHexLower(length_node.getRoot(pool))});
    }

    var l: usize = 0;
    for (0..subtree_count) |subtree_i| {
        // std.debug.print("=== Processing subtree {} ===\n", .{subtree_i});
        // std.debug.print("current n: {}, hash: {}\n", .{ n, std.fmt.fmtSliceHexLower(n.getRoot(pool)) });

        errdefer {
            // log.debug("--- FAILED at Subtree {} ---", .{subtree_i});
            // log.debug("current n hash: {}", .{std.fmt.fmtSliceHexLower(n.getRoot(pool))});
            // log.debug("subtree_length={}, subtree_depth={}, l={}", .{ @min(subtreeLength(subtree_i), out.len - l), subtreeDepth(subtree_i), l });
        }

        // Read order per step = RIGHT then LEFT
        // Reason: RIGHT holds the current group; LEFT continues the progressive chain.
        // If false: You read zeros/padding as real elements; order and counts are wrong.
        const subtree_length = @min(subtreeLength(subtree_i), out.len - l);
        const subtree_depth = subtreeDepth(subtree_i);
        // std.debug.print("subtree_length={}, subtree_depth={}\n", .{ subtree_length, subtree_depth });
        // std.debug.print("About to call n.getRight() on node {}\n", .{n});

        const subtree_root = n.getRight(pool) catch |err| {
            // std.debug.print("ERROR getting n.getRight at subtree {}: {}\n", .{ subtree_i, err });
            // If we can't get right child from zero node, it means no data/subtree here
            // Yield zeros for this subtree section
            if (@intFromEnum(n) == 0) {
                // std.debug.print("Zero node: yielding zeros for subtree positions\n", .{});
                for (l..l + subtree_length) |pos| {
                    if (pos < out.len) {
                        out[pos] = @enumFromInt(0);
                    }
                }
                l += subtree_length;
                // Continue to next level - n is already zero, so n.getLeft() will also be zero
                n = @enumFromInt(0);
                continue;
            }
            // log.debug("ERROR getting n.getRight at subtree {}: {}", .{ subtree_i, err });
            return err;
        };
        // std.debug.print("Got subtree_root: {}, hash: {}\n", .{ subtree_root, std.fmt.fmtSliceHexLower(subtree_root.getRoot(pool)) });

        if (subtree_depth == 0) {
            // Depth-0 subtree: the subtree_root is already the leaf node
            if (subtree_length != 1) {
                // log.debug("ERROR: depth-0 subtree should have length 1, got {}", .{subtree_length});
                return error.InvalidSubtreeLength;
            }
            out[l] = subtree_root;
        } else {
            // Depth > 0: navigate the subtree to get nodes at depth
            subtree_root.getNodesAtDepth(pool, subtree_depth, 0, out[l .. l + subtree_length]) catch |err| {
                // log.debug("ERROR getNodesAtDepth: {}", .{err});
                return err;
            };
        }
        l += subtree_length;
        // std.debug.print("Moving to next progressive chain node with n.getLeft()\n", .{});
        n = n.getLeft(pool) catch |err| {
            // std.debug.print("ERROR getting n.getLeft: {}\n", .{err});
            // log.debug("ERROR getting n.getLeft: {}", .{err});
            return err;
        };
        // std.debug.print("Next n: {}, hash: {}\n", .{ n, std.fmt.fmtSliceHexLower(n.getRoot(pool)) });
    }

    // Terminator = final LEFT is zero
    // Reason: Progressive chain ends with a zero node after consuming all groups.
    // If false: You walked the wrong side or started from the wrong node.
    if (!std.mem.eql(u8, &n.getRoot(pool).*, &[_]u8{0} ** 32)) {
        // log.debug("TERMINATOR MISMATCH:", .{});
        // log.debug("final n hash: {}", .{std.fmt.fmtSliceHexLower(n.getRoot(pool))});
        // log.debug("zero hash: {}", .{std.fmt.fmtSliceHexLower(&[_]u8{0} ** 32)});
        return error.InvalidTerminatorNode;
    }
}

pub fn fillWithContents(allocator: std.mem.Allocator, pool: *Node.Pool, nodes: []Node.Id, should_ref: bool) !Node.Id {
    const subtree_count = subtreeIndex(nodes.len);

    errdefer {
        // log.debug("=== fillWithContents FAILED ===", .{});
        // log.debug("nodes.len={}, subtree_count={}", .{ nodes.len, subtree_count });
    }

    var n: Node.Id = @enumFromInt(0);

    // Calculate starting positions for each subtree first
    var subtree_starts = std.ArrayList(usize).init(allocator);
    defer subtree_starts.deinit();
    var pos: usize = 0;
    for (0..subtree_count) |subtree_i| {
        try subtree_starts.append(pos);
        pos += @min(subtreeLength(subtree_i), nodes.len - pos);
    }

    for (0..subtree_count) |i| {
        const subtree_i = subtree_count - 1 - i;
        const subtree_depth = subtreeDepth(subtree_i);
        const l = subtree_starts.items[subtree_i];
        const subtree_length = @min(subtreeLength(subtree_i), nodes.len - l);

        errdefer {
            // log.debug("--- FAILED Building subtree {} ---", .{subtree_i});
            // log.debug("subtree_depth={}, subtree_length={}, l={}", .{ subtree_depth, subtree_length, l });
            // log.debug("current remainder hash: {}", .{std.fmt.fmtSliceHexLower(n.getRoot(pool))});
        }

        const subtree_root = Node.fillWithContents(pool, nodes[l .. l + subtree_length], subtree_depth, false) catch |err| {
            // log.debug("ERROR Node.fillWithContents: {}", .{err});
            return err;
        };

        // Build order per step = Pair(LEFT=remainder, RIGHT=subtree_root)
        // Reason: Must match the read order and spec orientation.
        // If false: Contents tree is mirrored; proofs don't match gindices.
        n = pool.createBranch(
            n,
            subtree_root,
            should_ref,
        ) catch |err| {
            // log.debug("ERROR createBranch: {}", .{err});
            // log.debug("  left (remainder): {}", .{std.fmt.fmtSliceHexLower(n.getRoot(pool))});
            // log.debug("  right (subtree): {}", .{std.fmt.fmtSliceHexLower(subtree_root.getRoot(pool))});
            return err;
        };
    }

    return n;
}
