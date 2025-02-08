const std = @import("std");
const Scanner = std.json.Scanner;
const Allocator = std.mem.Allocator;
const AllocatorError = Allocator.Error;
const NextError = Scanner.NextError;
const FromHexError = @import("util").FromHexError;
const TreeError = @import("persistent_merkle_tree").TreeError;

pub const ScannerError = NextError;
pub const ParseUIntError = error{ InvalidNumber, Overflow, InvalidChacter } || std.fmt.ParseIntError || std.fmt.ParseFloatError || AllocatorError || ScannerError;
pub const JsonError = ParseUIntError || FromHexError || error{ InvalidJson, InCorrectLen, InvalidLength };
pub const SszError = AllocatorError || error{ OutOfMemory, InCorrectLen, InvalidLength } || error{ invalidFixedSize, zeroOffset, offsetNotDivisibleBy4, offsetOutOfRange, offsetNotIncreasing, InvalidSsz } || error{MissingPool};
pub const HashError = error{ InCorrectLen, InvalidInput, noInitZeroHash, OutOfBounds, OutOfMemory };
pub const ViewDUError = SszError || TreeError || error{MissingPool};
