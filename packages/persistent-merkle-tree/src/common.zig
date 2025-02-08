const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorError = Allocator.Error;
const nm = @import("./node.zig");
pub const TreeError = nm.NodeError || error{InvalidLength};
