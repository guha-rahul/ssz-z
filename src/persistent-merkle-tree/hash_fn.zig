pub const HashError = error{
    InvalidInput,
};

pub const HashFn = *const fn (in: []const [32]u8, out: [][32]u8) HashError!void;
