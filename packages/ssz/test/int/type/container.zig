const std = @import("std");
const TestCase = @import("common.zig").TypeTestCase;
const UintType = @import("ssz").UintType;
const FixedContainerType = @import("ssz").FixedContainerType;
const VariableContainerType = @import("ssz").VariableContainerType;
const FixedListType = @import("ssz").FixedListType;

test "ContainerType" {
    const test_cases = [_]TestCase{
        TestCase{
            .id = "empty",
            .serializedHex = "0x00000000000000000000000000000000",
            .json =
            \\{"a":"0","b":"0"}
            ,
            .rootHex = "0x0000000000000000000000000000000000000000000000000000000000000000",
        },
        TestCase{
            .id = "simple",
            .serializedHex = "0x01000000000000000000000000000000",
            .json =
            \\{"a":"1","b":"0"}
            ,
            .rootHex = "0x5c597e77f879e249af95fe543cf5f4dd16b686948dc719707445a32a77ff6266",
        },
    };

    const allocator = std.testing.allocator;

    const Container = FixedContainerType(struct {
        a: UintType(64),
        b: UintType(64),
    });

    const TypeTest = @import("common.zig").typeTest(Container);

    for (test_cases[0..]) |*tc| {
        try TypeTest.run(allocator, tc);
    }
}

test "ContainerType with FixedListType(uint64, 128) and uint64" {
    const allocator = std.testing.allocator;

    const Container = VariableContainerType(struct {
        a: FixedListType(UintType(64), 128),
        b: UintType(64),
    });

    const TypeTest = @import("common.zig").typeTest(Container);

    const test_cases = [_]TestCase{
        TestCase{
            .id = "empty",
            .serializedHex = "0x0c0000000000000000000000",
            .json =
            \\{"a":[],"b":"0"}
            ,
            .rootHex = "0x0000000000000000000000000000000000000000000000000000000000000000",
        },
        TestCase{
            .id = "simple",
            .serializedHex = "0x0c00000000000000000000000100000000000000",
            .json =
            \\{"a":["1"],"b":"0"}
            ,
            .rootHex = "0x5c597e77f879e249af95fe543cf5f4dd16b686948dc719707445a32a77ff6266",
        },
    };

    for (test_cases[0..]) |*tc| {
        try TypeTest.run(allocator, tc);
    }
}
