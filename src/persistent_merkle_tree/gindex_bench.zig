const std = @import("std");
const zbench = @import("zbench");

const Gindex = @import("gindex.zig").Gindex;
const toPathBits = @import("gindex.zig").toPathBits;
const toPath = @import("gindex.zig").toPath;
const pathLen = @import("gindex.zig").pathLen;
const max_depth = @import("gindex.zig").max_depth;

const PathBits = struct {
    gindex: Gindex,
    pub fn run(self: PathBits, allocator: std.mem.Allocator) void {
        _ = allocator;
        var bits_buf: [max_depth]u1 = undefined;
        const bits = toPathBits(self.gindex, &bits_buf);
        for (bits) |bit| {
            std.mem.doNotOptimizeAway(bit);
        }
    }
};

const Path = struct {
    gindex: Gindex,
    pub fn run(self: Path, allocator: std.mem.Allocator) void {
        _ = allocator;
        var path = toPath(self.gindex);
        var path_len = pathLen(self.gindex);
        while (path_len > 0) {
            path_len -= 1;
            std.mem.doNotOptimizeAway(path & 1);
            path >>= 1;
        }
    }
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();
    var bench = zbench.Benchmark.init(allocator, .{});
    defer bench.deinit();

    const gindex: Gindex = 0x123456789abcdef0;
    const path_bits = PathBits{ .gindex = gindex };
    try bench.addParam("gindex - path_bits", &path_bits, .{});
    const path = Path{ .gindex = gindex };
    try bench.addParam("gindex - path", &path, .{});

    try bench.run(stdout);
}
