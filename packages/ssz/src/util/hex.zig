const std = @import("std");

pub const FromHexError = error{
    InvalidHexLength,
    InvalidOutputLength,
    InvalidHexDigit,
};

/// convert to root with "0x" prefix
pub fn toRootHex(root: *const [32]u8) ![66]u8 {
    var buffer = [_]u8{0} ** 66;

    var stream = std.io.fixedBufferStream(&buffer); // Mutable stream object
    const writer = stream.writer(); // Get a mutable writer from the stream
    try writer.writeByte('0');
    try writer.writeByte('x');

    for (root) |b| {
        try std.fmt.format(writer, "{x:0>2}", .{b});
    }
    return buffer;
}

pub fn fromHex(hex: []const u8, out: []u8) !usize {
    if (hex.len == 0) {
        return 0;
    }

    const hex_value = if (hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X')) hex[2..] else hex;

    if (hex_value.len % 2 != 0) {
        return error.InvalidHexLength;
    }

    if (hex_value.len / 2 != out.len) {
        return error.InvalidOutputLength;
    }

    var i: usize = 0;
    while (i < hex_value.len) {
        const high = try parseHexDigit(hex_value[i]);
        const low = try parseHexDigit(hex_value[i + 1]);
        out[i / 2] = high << 4 | low;
        i += 2;
    }

    return i;
}

pub fn hasOxPrefix(hex: []const u8) bool {
    return hex[0] == '0' and hex[1] == 'x';
}

pub fn hexByteLen(hex: []const u8) usize {
    return if (hasOxPrefix(hex)) (hex - 2) / 2 else hex / 2;
}

fn parseHexDigit(digit: u8) !u8 {
    switch (digit) {
        '0'...'9' => return digit - '0',
        'a'...'f' => return digit - 'a' + 10,
        'A'...'F' => return digit - 'A' + 10,
        else => return error.InvalidHexDigit,
    }
}

test "toRootHex" {
    const TestCase = struct {
        root: *const [32]u8,
        expected: []const u8,
    };

    const test_cases = [_]TestCase{
        TestCase{ .root = &[_]u8{0} ** 32, .expected = "0x0000000000000000000000000000000000000000000000000000000000000000" },
        TestCase{ .root = &[_]u8{10} ** 32, .expected = "0x0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a" },
        TestCase{ .root = &[_]u8{17} ** 32, .expected = "0x1111111111111111111111111111111111111111111111111111111111111111" },
        TestCase{ .root = &[_]u8{255} ** 32, .expected = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" },
    };

    for (test_cases) |tc| {
        const hex = try toRootHex(tc.root);
        try std.testing.expectEqualSlices(u8, tc.expected, &hex);
    }
}

test "fromHex" {
    const TestCase = struct {
        hex: []const u8,
        expected: []const u8,
    };

    const test_cases = comptime [_]TestCase{
        TestCase{ .hex = "00000000", .expected = &[_]u8{ 0, 0, 0, 0 } },
        TestCase{ .hex = "c78009fd", .expected = &[_]u8{ 199, 128, 9, 253 } },
        TestCase{ .hex = "C78009FD", .expected = &[_]u8{ 199, 128, 9, 253 } },
        TestCase{ .hex = "0x00000000", .expected = &[_]u8{ 0, 0, 0, 0 } },
        TestCase{ .hex = "0xc78009fd", .expected = &[_]u8{ 199, 128, 9, 253 } },
        TestCase{ .hex = "0xC78009FD", .expected = &[_]u8{ 199, 128, 9, 253 } },
    };

    inline for (test_cases) |tc| {
        var out = [_]u8{0} ** tc.expected.len;
        _ = try fromHex(tc.hex, out[0..]);
        try std.testing.expectEqualSlices(u8, tc.expected, out[0..]);
    }
}
