const std = @import("std");
const toRootHex = @import("util").toRootHex;
const fromHex = @import("util").fromHex;
const TestCase = @import("common.zig").TypeTestCase;
const FixedListType = @import("ssz").FixedListType;
const UintType = @import("ssz").UintType;

const test_cases = [_]TestCase{
    .{ .id = "empty", .serializedHex = "0x", .json = 
    \\"0x"
    , .rootHex = "0xe8e527e84f666163a90ef900e013f56b0a4d020148b2224057b719f351b003a6" },
    .{ .id = "4 bytes zero", .serializedHex = "0x00000000", .json = 
    \\"0x00000000"
    , .rootHex = "0xa39babe565305429771fc596a639d6e05b2d0304297986cdd2ef388c1936885e" },
    .{
        .id = "4 bytes some value",
        .serializedHex = "0x0cb94737",
        .json =
        \\"0x0cb94737"
        ,
        .rootHex = "0x2e14da116ecbec4c8d693656fb5b69bb0ea9e84ecdd15aba7be1c008633f2885",
    },
    .{
        .id = "32 bytes zero",
        .serializedHex = "0x0000000000000000000000000000000000000000000000000000000000000000",
        .json =
        \\"0x0000000000000000000000000000000000000000000000000000000000000000"
        ,
        .rootHex = "0xbae146b221eca758702e29b45ee7f7dc3eea17d119dd0a3094481e3f94706c96",
    },
    .{
        .id = "32 bytes some value",
        .serializedHex = "0x0cb947377e177f774719ead8d210af9c6461f41baf5b4082f86a3911454831b8",
        .json =
        \\"0x0cb947377e177f774719ead8d210af9c6461f41baf5b4082f86a3911454831b8"
        ,
        .rootHex = "0x50425dbd7a34b50b20916e965ce5c060abe6516ac71bb00a4afebe5d5c4568b8",
    },
    .{
        .id = "96 bytes zero",
        .serializedHex = "0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
        .json =
        \\"0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        ,
        .rootHex = "0xcd09661f4b2109fb26decd60c004444ea5308a304203412280bd2af3ace306bf",
    },
    .{
        .id = "96 bytes some value",
        .serializedHex = "0xb55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1b55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1b55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1",
        .json =
        \\"0xb55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1b55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1b55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1"
        ,
        .rootHex = "0x5d3ae4b886c241ffe8dc7ae1b5f0e2fb9b682e1eac2ddea292ef02cc179e6903",
    },
    .{
        .id = "short value",
        .serializedHex = "0xb55b8592bcac475906631481bbc746bc",
        .json = "\"0xb55b8592bcac475906631481bbc746bc\"",
        .rootHex = "0x9ab378cfbd6ec502da1f9640fd956bbef1f9fcbc10725397805c948865384e77",
    },
    .{
        .id = "long value",
        .serializedHex = "0xb55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1b55b8592bc",
        .json = "\"0xb55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1b55b8592bc\"",
        .rootHex = "0x4b71a7de822d00a5ff8e7e18e13712a50424cbc0e18108ab1796e591136396a0",
    },
};

fn toJsonStr(allocator: std.mem.Allocator, bytes: []const u8) !std.ArrayList(u8) {
    var list = std.ArrayList(u8).init(allocator);
    try list.appendSlice("[");
    for (bytes, 0..) |byte, i| {
        if (i > 0) try list.appendSlice(",");
        var buf: [4]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, "\"{d}\"", .{byte});
        try list.appendSlice(str);
    }
    try list.appendSlice("]");
    return list;
}

test "ByteListType" {
    const allocator = std.testing.allocator;
    const List = FixedListType(UintType(8), 256);

    const TypeTest = @import("common.zig").typeTest(List);

    for (test_cases[0..]) |*tc| {
        // skip 0x and 2 double quotes
        const u8_list = try allocator.alloc(u8, ((tc.json.len - 4) / 2));
        defer allocator.free(u8_list);

        // skip double quotes at the start and end of json string
        _ = try fromHex(tc.json[1..(tc.json.len - 1)], u8_list);
        const json_array_list = try toJsonStr(allocator, u8_list);
        defer json_array_list.deinit();

        try TypeTest.run(allocator, &.{
            .id = tc.id,
            .serializedHex = tc.serializedHex,
            .json = json_array_list.items,
            .rootHex = tc.rootHex,
        });
    }
}
