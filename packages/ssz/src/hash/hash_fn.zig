pub const HashError = error{
    InvalidInput,
};

pub const HashFn = *const fn (in: []const u8, out: []u8) HashError!void;
