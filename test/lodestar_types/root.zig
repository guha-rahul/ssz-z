const std = @import("std");
const testing = std.testing;

const primitive = @import("./primitive.zig");
const phase0 = @import("./phase0.zig");

test {
    testing.refAllDecls(phase0);

    // inline for (@typeInfo(phase0).@"struct".decls) |decl| {}
}

const src = blk: {
    var buf: []const u8 = "";
    buf = buf ++ "const std = @import(\"std\");\n";
    buf = buf ++ writeExportedUint("uint64", primitive.Slot);
    break :blk buf;
};

pub fn main() void {
    std.debug.print("{s}\n", .{src});
}

const comptimePrint = std.fmt.comptimePrint;

fn writeExportedUint(comptime name: []const u8, T: type) []const u8 {
    return comptimePrint("export const {s}_kind = {d};\n", .{ name, @intFromEnum(T.kind) }) ++
        comptimePrint("export const {s}_fixed_size = {d};\n", .{ name, T.fixed_size });
}
