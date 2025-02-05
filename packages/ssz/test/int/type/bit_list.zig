const std = @import("std");
const toRootHex = @import("util").toRootHex;
const fromHex = @import("util").fromHex;
const TestCase = @import("common.zig").TypeTestCase;
const FixedListType = @import("ssz").FixedListType;
const BoolType = @import("ssz").BoolType;

test "BitListType" {
    const test_cases = [_]TestCase{
        TestCase{
            .id = "empty",
            .serializedHex = "0x01",
            .json = "[]",
            .rootHex = "0xe8e527e84f666163a90ef900e013f56b0a4d020148b2224057b719f351b003a6",
        },
        TestCase{
            .id = "zero'ed 1 bytes",
            .serializedHex = "0x0010",
            .json = "[false, false, false, false]",
            .rootHex = "0x07eb640282e16eea87300c374c4894ad69b948de924a158d2d1843b3cf01898a",
        },
        TestCase{
            .id = "zero'ed 8 bytes",
            .serializedHex = "0x000000000000000010",
            .json = "[false, false, false, false, false, false, false, false]",
            .rootHex = "0x5c597e77f879e249af95fe543cf5f4dd16b686948dc719707445a32a77ff6266",
        },
        TestCase{
            .id = "short value",
            .serializedHex = "0xb55b8592bcac475906631481bbc746bc",
            .json = "[true, false, true, true, false, true, false, true]",
            .rootHex = "0x9ab378cfbd6ec502da1f9640fd956bbef1f9fcbc10725397805c948865384e77",
        },
        TestCase{
            .id = "long value",
            .serializedHex = "0xb55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1b55b8592bc",
            .json = "[true, false, true, true, false, true, false, true, true, true, false, false, true, false, true, true]",
            .rootHex = "0x4b71a7de822d00a5ff8e7e18e13712a50424cbc0e18108ab1796e591136396a0",
        },
    };

    const allocator = std.testing.allocator;
    const List = FixedListType(BoolType(), 2048);

    const TypeTest = @import("common.zig").typeTest(List);

    for (test_cases[0..]) |*tc| {
        try TypeTest.run(allocator, tc);
    }
}
