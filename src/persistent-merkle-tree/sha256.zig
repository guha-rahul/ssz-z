const std = @import("std");
const HashError = @import("hash_fn.zig").HashError;
const HashFn = @import("hash_fn.zig").HashFn;

const Sha256 = std.crypto.hash.sha2.Sha256;

pub fn digest64Into(obj1: *const [32]u8, obj2: *const [32]u8, out: *[32]u8) void {
    var h = Sha256.init(.{});
    h.update(obj1);
    h.update(obj2);
    h.final(out);
}

comptime {
    std.debug.assert(@TypeOf(&sha256Hash) == HashFn);
}

pub fn sha256Hash(in: []const [32]u8, out: [][32]u8) HashError!void {
    if (in.len % 2 != 0) {
        return error.InvalidInput;
    }

    if (in.len != 2 * out.len) {
        return error.InvalidInput;
    }

    for (0..in.len / 2) |i| {
        // calling digest64Into is slow so call Sha256.hash() directly
        Sha256.hash(@ptrCast(in[i * 2 .. i * 2 + 2]), &out[i], .{});
    }
}

test "digest64Into works correctly" {
    const obj1: [32]u8 = [_]u8{1} ** 32;
    const obj2: [32]u8 = [_]u8{2} ** 32;
    var hash_result: [32]u8 = undefined;

    // Call the function and ensure it works without error
    digest64Into(&obj1, &obj2, &hash_result);

    // Print the hash for manual inspection (optional)
    // std.debug.print("Hash value: {any}\n", .{hash_result});
    // std.debug.print("Hash hex: {s}\n", .{std.fmt.bytesToHex(hash_result, .lower)});
    // try std.testing.expect(mem.eql(u8, &hash_result, &expected_hash));
}

test "hashInto" {
    const in = [_][32]u8{[_]u8{1} ** 32} ** 4;
    var out: [2][32]u8 = undefined;
    try sha256Hash(&in, &out);
    // std.debug.print("@@@ out: {any}\n", .{out});
    var out2: [32]u8 = undefined;
    digest64Into(&in[0], &in[2], &out2);
    // std.debug.print("@@@ out2: {any}\n", .{out2});
    try std.testing.expectEqualSlices(u8, &out2, &out[0]);
    try std.testing.expectEqualSlices(u8, &out2, &out[1]);
}

// test {
//     for (0..50) |i|
//         std.debug.print("({})={}\n", .{ i, (@sizeOf(usize) * 8) - @clz(i) });
// }
