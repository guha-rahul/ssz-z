const std = @import("std");
const yaml = @import("yaml");
const spec_test_options = @import("spec_test_options");
const types = @import("general_types.zig");
const snappy = @import("snappy");
const hex = @import("hex");
const ssz = @import("ssz");

const Allocator = std.mem.Allocator;

fn validTestCase(comptime ST: type, gpa: Allocator, path: std.fs.Dir) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    // read expected root

    const meta_file = try path.openFile("meta.yaml", .{});
    defer meta_file.close();
    const Meta = struct {
        root: []const u8,
    };
    const meta_bytes = try meta_file.readToEndAlloc(allocator, 1_000);

    var meta_yaml = yaml.Yaml{ .source = meta_bytes };
    try meta_yaml.load(allocator);
    const meta = try meta_yaml.parse(allocator, Meta);

    const root_expected = try hex.hexToRoot(meta.root[0..66]);

    // read expected value

    const value_file = try path.openFile("value.yaml", .{});
    defer value_file.close();
    const value_bytes = try value_file.readToEndAlloc(allocator, 1_000_000);

    var value_yaml = yaml.Yaml{ .source = value_bytes };
    try value_yaml.load(allocator);
    const value_expected = try value_yaml.parse(allocator, ST.Type);

    // read expected serialized

    const serialized_file = try path.openFile("serialized.ssz_snappy", .{});
    defer serialized_file.close();
    const serialized_snappy_bytes = try serialized_file.readToEndAlloc(allocator, 1_000_000);

    const serialized_buf = try allocator.alloc(u8, try snappy.uncompressedLength(serialized_snappy_bytes));
    const serialized_len = try snappy.uncompress(serialized_snappy_bytes, serialized_buf);
    const serialized_expected = serialized_buf[0..serialized_len];

    // test serialization

    const serialized_actual = try allocator.alloc(
        u8,
        if (comptime ssz.isFixedType(ST)) ST.fixed_size else ST.serializedSize(&value_expected),
    );
    _ = ST.serializeIntoBytes(&value_expected, serialized_actual);
    try std.testing.expectEqualSlices(u8, serialized_expected, serialized_actual);

    // test deserialization

    var value_actual: ST.Type = if (comptime ssz.isFixedType(ST))
        undefined
    else
        try ST.defaultValue(allocator);
    if (comptime ssz.isFixedType(ST)) {
        try ST.deserializeFromBytes(serialized_expected, &value_actual);
    } else {
        try ST.deserializeFromBytes(allocator, serialized_expected, &value_actual);
    }
    try std.testing.expectEqualDeep(value_expected, value_actual);

    // test merkleization

    const Hasher = ssz.Hasher(ST);
    var hash_scratch = try Hasher.init(allocator);
    var root_actual: [32]u8 = undefined;
    try Hasher.hash(&hash_scratch, &value_expected, &root_actual);
    try std.testing.expectEqualSlices(u8, &root_expected, &root_actual);
}

test "vec_bool_1_max" {
    const allocator = std.testing.allocator;
    const p = try std.fs.path.join(allocator, &[_][]const u8{
        spec_test_options.spec_test_out_dir,
        spec_test_options.spec_test_version,
        "general",
        "tests",
        "general",
        "phase0",
        "ssz_generic",
        "basic_vector",
        "valid",
        "vec_bool_1_max",
    });
    defer allocator.free(p);
    const test_dir = try std.fs.cwd().openDir(p, .{});
    try validTestCase(types.vec_bool_1, allocator, test_dir);
}
