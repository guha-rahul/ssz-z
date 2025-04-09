const std = @import("std");
const digest64Into = @import("sha256.zig").digest64Into;

pub fn ZeroHash(max_depth: usize) type {
    comptime {
        if (max_depth == 0) {
            @compileError("max_depth must be non-zero");
        }
    }

    return struct {
        hashes: [max_depth][32]u8,

        pub fn init() @This() {
            // It seems that the default sha2 implementation does a lot of comptime execution
            @setEvalBranchQuota(max_depth * 10000);

            var zh: @This() = undefined;
            for (0..max_depth) |i| {
                if (i == 0) {
                    zh.hashes[i] = [_]u8{0} ** 32;
                } else {
                    digest64Into(
                        &(zh.hashes[i - 1]),
                        &(zh.hashes[i - 1]),
                        &zh.hashes[i],
                    );
                }
            }
            return zh;
        }

        pub fn get(self: *const @This(), depth: usize) !*const [32]u8 {
            if (depth >= max_depth) {
                return error.OutOfBounds;
            }

            return &self.hashes[depth];
        }
    };
}

const build_options = @import("build_options");

// this helps avoid heap memory allocation in setNodesAtDepth() below
// VALIDATOR_REGISTRY_LIMIT is only 2**40 (= 1,099,511,627,776)
const default_max_depth = 64;

// Allow overriding via `build.zig`
pub const zero_hash_max_depth: usize = if (@hasDecl(build_options, "zero_hash_max_depth"))
    if (@typeInfo(@TypeOf(build_options.zero_hash_max_depth)) == .optional)
        build_options.zero_hash_max_depth orelse default_max_depth
    else
        build_options.zero_hash_max_depth
else
    default_max_depth;

pub const zero_hash = ZeroHash(zero_hash_max_depth).init();
pub fn getZeroHash(depth: usize) !*const [32]u8 {
    return zero_hash.get(depth);
}

test "ZeroHash" {
    const hash = try zero_hash.get(1);
    const expected_hash = [_]u8{
        245, 165, 253, 66,  209, 106, 32,  48,
        39,  152, 239, 110, 211, 9,   151, 155,
        67,  0,   61,  35,  32,  217, 240, 232,
        234, 152, 49,  169, 39,  89,  251, 75,
    };
    try std.testing.expectEqualSlices(u8, &hash.*, &expected_hash);
    // std.debug.print("Hash value: {any}\n", .{hash});
}
