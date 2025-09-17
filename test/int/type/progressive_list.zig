const std = @import("std");
const ssz = @import("ssz");

const types = ssz.types;
const TestCase = @import("common.zig").TypeTestCase;

test "ProgressiveListType(u64) vector tests" {
    const a = std.testing.allocator;
    const U64 = types.UintType(64);
    const PList = types.ProgressiveListType(U64, 1024);
    const TypeTest = @import("common.zig").typeTest(PList);

    const testCases = [_]TestCase{
        TestCase{ .id = "empty", .serializedHex = "0x", .json = "[]", .rootHex = "0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b" },
        TestCase{ .id = "4 values", .serializedHex = "0xa086010000000000400d030000000000e093040000000000801a060000000000", .json = "[\"100000\",\"200000\",\"300000\",\"400000\"]", .rootHex = "0x38fc50464faabda97fefa5c8d82c429ab1266e2ca58a375cac08f255cf78b82c" },
        TestCase{ .id = "8 values", .serializedHex = "0xa086010000000000400d030000000000e093040000000000801a060000000000a086010000000000400d030000000000e093040000000000801a060000000000", .json = "[\"100000\",\"200000\",\"300000\",\"400000\",\"100000\",\"200000\",\"300000\",\"400000\"]", .rootHex = "0xfd8b579369890fb42a953a758d25253689be141472fa865f74c14fc8f4853957" },
    };

    for (testCases[0..]) |*tc| {
        try TypeTest.run(a, tc);
    }
}

test "ProgressiveList(u64) serialized.hashTreeRoot smoke" {
    const allocator = std.heap.page_allocator;
    const T = ssz.types.ProgressiveListType(ssz.types.UintType(64), 1024);

    var v = T.default_value;
    try v.append(allocator, @as(u64, 1));
    try v.append(allocator, @as(u64, 2));
    try v.append(allocator, @as(u64, 3));
    try v.append(allocator, @as(u64, 4));

    const size = T.serializedSize(&v);
    const buf = try allocator.alloc(u8, size);
    defer allocator.free(buf);
    _ = T.serializeIntoBytes(&v, buf);

    var out: [32]u8 = undefined;
    try T.serialized.hashTreeRoot(allocator, buf, &out);

    var out2: [32]u8 = undefined;
    try T.hashTreeRoot(allocator, &v, &out2);

    try std.testing.expect(!std.mem.allEqual(u8, out[0..], 0));
    try std.testing.expectEqual(out, out2);
}

test "ProgressiveList(u64) serialized.hashTreeRoot length mix-in check" {
    const allocator = std.heap.page_allocator;
    const T = ssz.types.ProgressiveListType(ssz.types.UintType(64), 1024);

    var v = T.default_value;
    try v.append(allocator, @as(u64, 1));
    try v.append(allocator, @as(u64, 2));
    try v.append(allocator, @as(u64, 3));
    try v.append(allocator, @as(u64, 4));

    const size = T.serializedSize(&v);
    const buf = try allocator.alloc(u8, size);
    defer allocator.free(buf);
    _ = T.serializeIntoBytes(&v, buf);

    var h_ser4: [32]u8 = undefined;
    try T.serialized.hashTreeRoot(allocator, buf, &h_ser4);

    // Now compute for 3 elements and ensure it differs, demonstrating length contributes
    var v3 = T.default_value;
    try v3.append(allocator, @as(u64, 1));
    try v3.append(allocator, @as(u64, 2));
    try v3.append(allocator, @as(u64, 3));
    const size3 = T.serializedSize(&v3);
    const buf3 = try allocator.alloc(u8, size3);
    defer allocator.free(buf3);
    _ = T.serializeIntoBytes(&v3, buf3);
    var h_ser3: [32]u8 = undefined;
    try T.serialized.hashTreeRoot(allocator, buf3, &h_ser3);
    try std.testing.expect(!std.mem.eql(u8, h_ser3[0..], h_ser4[0..]));
}

test "ProgressiveList(u64) boundary at 33 items" {
    const allocator = std.heap.page_allocator;
    const T = ssz.types.ProgressiveListType(ssz.types.UintType(64), 1024);

    var v = T.default_value;
    var i: u64 = 0;
    while (i < 33) : (i += 1) {
        try v.append(allocator, i);
    }

    const size = T.serializedSize(&v);
    const buf = try allocator.alloc(u8, size);
    defer allocator.free(buf);
    _ = T.serializeIntoBytes(&v, buf);

    var a: [32]u8 = undefined;
    var b: [32]u8 = undefined;
    try T.serialized.hashTreeRoot(allocator, buf, &a);
    try T.hashTreeRoot(allocator, &v, &b);
    try std.testing.expectEqual(a, b);
}

// 1) Empty list: serialized hashing should be hashPair(zeroChunkRoot, length=0)
test "ProgressiveList(u64) empty list root" {
    const allocator = std.heap.page_allocator;
    const T = ssz.types.ProgressiveListType(ssz.types.UintType(64), 8);

    var v = T.default_value;

    const size = T.serializedSize(&v);
    try std.testing.expectEqual(@as(usize, 0), size);

    var a: [32]u8 = undefined;
    var b: [32]u8 = undefined;
    try T.hashTreeRoot(allocator, &v, &a);
    try T.serialized.hashTreeRoot(allocator, &[_]u8{}, &b);

    try std.testing.expectEqual(a, b);
}

// 2) Max capacity boundary: exactly limit elements must work
// Note: append is not limit-enforced in-memory; we validate equality at limit.
test "ProgressiveList(u64) capacity boundary" {
    const allocator = std.heap.page_allocator;
    const limit = 64;
    const T = ssz.types.ProgressiveListType(ssz.types.UintType(64), limit);

    var v = T.default_value;
    var i: u64 = 0;
    while (i < limit) : (i += 1) try v.append(allocator, i);

    const size = T.serializedSize(&v);
    const buf = try allocator.alloc(u8, size);
    defer allocator.free(buf);
    _ = T.serializeIntoBytes(&v, buf);

    var a: [32]u8 = undefined;
    var b: [32]u8 = undefined;
    try T.serialized.hashTreeRoot(allocator, buf, &a);
    try T.hashTreeRoot(allocator, &v, &b);
    try std.testing.expectEqual(a, b);
}

// 3) Randomized contents equality: value vs serialized path on 200 items
test "ProgressiveList(u64) randomized contents agree" {
    const allocator = std.heap.page_allocator;
    const T = ssz.types.ProgressiveListType(ssz.types.UintType(64), 1024);

    var v = T.default_value;

    var seed: u64 = 0xC0FFEE;
    const next = struct {
        fn f(s: *u64) u64 {
            var x = s.*;
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            s.* = x;
            return x;
        }
    }.f;
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const x: u64 = next(&seed) % 1_000_001;
        try v.append(allocator, x);
    }

    const size = T.serializedSize(&v);
    const buf = try allocator.alloc(u8, size);
    defer allocator.free(buf);
    _ = T.serializeIntoBytes(&v, buf);

    var a: [32]u8 = undefined;
    var b: [32]u8 = undefined;
    try T.serialized.hashTreeRoot(allocator, buf, &a);
    try T.hashTreeRoot(allocator, &v, &b);
    try std.testing.expectEqual(a, b);
}

// 4) ProgressiveList of fixed composite elements should still match
test "ProgressiveList(fixed composite) equals serialized path" {
    const allocator = std.heap.page_allocator;
    const Pair = ssz.types.FixedContainerType(struct { a: ssz.types.UintType(32), b: ssz.types.UintType(32) });
    const T = ssz.types.ProgressiveListType(Pair, 64);

    var v = T.default_value;

    var k: u32 = 0;
    while (k < 12) : (k += 1) {
        var p: Pair.Type = Pair.default_value;
        p.a = k;
        p.b = k * 7 + 3;
        try v.append(allocator, p);
    }

    const size = T.serializedSize(&v);
    const buf = try allocator.alloc(u8, size);
    defer allocator.free(buf);
    _ = T.serializeIntoBytes(&v, buf);

    var a: [32]u8 = undefined;
    var b: [32]u8 = undefined;
    try T.serialized.hashTreeRoot(allocator, buf, &a);
    try T.hashTreeRoot(allocator, &v, &b);
    try std.testing.expectEqual(a, b);
}

// 5) ProgressiveList of variable elements (ByteList<16>) matches
test "ProgressiveList(ByteList<16>) variable elements match" {
    const allocator = std.heap.page_allocator;
    const Elem = ssz.types.ByteListType(16);
    const T = ssz.types.ProgressiveListType(Elem, 32);

    var v = T.default_value;

    // short
    {
        var e: Elem.Type = Elem.default_value;
        try e.append(allocator, 0xAB);
        try e.append(allocator, 0xCD);
        try v.append(allocator, e);
    }
    // long
    {
        var e: Elem.Type = Elem.default_value;
        var i: usize = 0;
        while (i < 15) : (i += 1) try e.append(allocator, @intCast(i));
        try v.append(allocator, e);
    }

    const size = T.serializedSize(&v);
    const buf = try allocator.alloc(u8, size);
    defer allocator.free(buf);
    _ = T.serializeIntoBytes(&v, buf);

    var a: [32]u8 = undefined;
    var b: [32]u8 = undefined;
    try T.serialized.hashTreeRoot(allocator, buf, &a);
    try T.hashTreeRoot(allocator, &v, &b);
    try std.testing.expectEqual(a, b);
}
