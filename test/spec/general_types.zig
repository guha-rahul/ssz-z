const ssz = @import("ssz");

// basic_vector
pub const vec_bool_1 = ssz.FixedVectorType(ssz.BoolType(), 1);
pub const vec_bool_2 = ssz.FixedVectorType(ssz.BoolType(), 2);
pub const vec_bool_3 = ssz.FixedVectorType(ssz.BoolType(), 3);
pub const vec_bool_4 = ssz.FixedVectorType(ssz.BoolType(), 4);
pub const vec_bool_5 = ssz.FixedVectorType(ssz.BoolType(), 5);
pub const vec_bool_8 = ssz.FixedVectorType(ssz.BoolType(), 8);
pub const vec_bool_16 = ssz.FixedVectorType(ssz.BoolType(), 16);
pub const vec_bool_31 = ssz.FixedVectorType(ssz.BoolType(), 31);
pub const vec_bool_512 = ssz.FixedVectorType(ssz.BoolType(), 512);
pub const vec_bool_513 = ssz.FixedVectorType(ssz.BoolType(), 513);
pub const vec_uint8_1 = ssz.FixedVectorType(ssz.UintType(8), 1);
pub const vec_uint8_2 = ssz.FixedVectorType(ssz.UintType(8), 2);
pub const vec_uint8_3 = ssz.FixedVectorType(ssz.UintType(8), 3);
pub const vec_uint8_4 = ssz.FixedVectorType(ssz.UintType(8), 4);
pub const vec_uint8_5 = ssz.FixedVectorType(ssz.UintType(8), 5);
pub const vec_uint8_8 = ssz.FixedVectorType(ssz.UintType(8), 8);
pub const vec_uint8_16 = ssz.FixedVectorType(ssz.UintType(8), 16);
pub const vec_uint8_31 = ssz.FixedVectorType(ssz.UintType(8), 31);
pub const vec_uint8_512 = ssz.FixedVectorType(ssz.UintType(8), 512);
pub const vec_uint8_513 = ssz.FixedVectorType(ssz.UintType(8), 513);
pub const vec_uint16_1 = ssz.FixedVectorType(ssz.UintType(16), 1);
pub const vec_uint16_2 = ssz.FixedVectorType(ssz.UintType(16), 2);
pub const vec_uint16_3 = ssz.FixedVectorType(ssz.UintType(16), 3);
pub const vec_uint16_4 = ssz.FixedVectorType(ssz.UintType(16), 4);
pub const vec_uint16_5 = ssz.FixedVectorType(ssz.UintType(16), 5);
pub const vec_uint16_8 = ssz.FixedVectorType(ssz.UintType(16), 8);
pub const vec_uint16_16 = ssz.FixedVectorType(ssz.UintType(16), 16);
pub const vec_uint16_31 = ssz.FixedVectorType(ssz.UintType(16), 31);
pub const vec_uint16_512 = ssz.FixedVectorType(ssz.UintType(16), 512);
pub const vec_uint16_513 = ssz.FixedVectorType(ssz.UintType(16), 513);
pub const vec_uint32_1 = ssz.FixedVectorType(ssz.UintType(32), 1);
pub const vec_uint32_2 = ssz.FixedVectorType(ssz.UintType(32), 2);
pub const vec_uint32_3 = ssz.FixedVectorType(ssz.UintType(32), 3);
pub const vec_uint32_4 = ssz.FixedVectorType(ssz.UintType(32), 4);
pub const vec_uint32_5 = ssz.FixedVectorType(ssz.UintType(32), 5);
pub const vec_uint32_8 = ssz.FixedVectorType(ssz.UintType(32), 8);
pub const vec_uint32_16 = ssz.FixedVectorType(ssz.UintType(32), 16);
pub const vec_uint32_31 = ssz.FixedVectorType(ssz.UintType(32), 31);
pub const vec_uint32_512 = ssz.FixedVectorType(ssz.UintType(32), 512);
pub const vec_uint32_513 = ssz.FixedVectorType(ssz.UintType(32), 513);
pub const vec_uint64_1 = ssz.FixedVectorType(ssz.UintType(64), 1);
pub const vec_uint64_2 = ssz.FixedVectorType(ssz.UintType(64), 2);
pub const vec_uint64_3 = ssz.FixedVectorType(ssz.UintType(64), 3);
pub const vec_uint64_4 = ssz.FixedVectorType(ssz.UintType(64), 4);
pub const vec_uint64_5 = ssz.FixedVectorType(ssz.UintType(64), 5);
pub const vec_uint64_8 = ssz.FixedVectorType(ssz.UintType(64), 8);
pub const vec_uint64_16 = ssz.FixedVectorType(ssz.UintType(64), 16);
pub const vec_uint64_31 = ssz.FixedVectorType(ssz.UintType(64), 31);
pub const vec_uint64_512 = ssz.FixedVectorType(ssz.UintType(64), 512);
pub const vec_uint64_513 = ssz.FixedVectorType(ssz.UintType(64), 513);
pub const vec_uint128_1 = ssz.FixedVectorType(ssz.UintType(128), 1);
pub const vec_uint128_2 = ssz.FixedVectorType(ssz.UintType(128), 2);
pub const vec_uint128_3 = ssz.FixedVectorType(ssz.UintType(128), 3);
pub const vec_uint128_4 = ssz.FixedVectorType(ssz.UintType(128), 4);
pub const vec_uint128_5 = ssz.FixedVectorType(ssz.UintType(128), 5);
pub const vec_uint128_8 = ssz.FixedVectorType(ssz.UintType(128), 8);
pub const vec_uint128_16 = ssz.FixedVectorType(ssz.UintType(128), 16);
pub const vec_uint128_31 = ssz.FixedVectorType(ssz.UintType(128), 31);
pub const vec_uint128_512 = ssz.FixedVectorType(ssz.UintType(128), 512);
pub const vec_uint128_513 = ssz.FixedVectorType(ssz.UintType(128), 513);
pub const vec_uint256_1 = ssz.FixedVectorType(ssz.UintType(256), 1);
pub const vec_uint256_2 = ssz.FixedVectorType(ssz.UintType(256), 2);
pub const vec_uint256_3 = ssz.FixedVectorType(ssz.UintType(256), 3);
pub const vec_uint256_4 = ssz.FixedVectorType(ssz.UintType(256), 4);
pub const vec_uint256_5 = ssz.FixedVectorType(ssz.UintType(256), 5);
pub const vec_uint256_8 = ssz.FixedVectorType(ssz.UintType(256), 8);
pub const vec_uint256_16 = ssz.FixedVectorType(ssz.UintType(256), 16);
pub const vec_uint256_31 = ssz.FixedVectorType(ssz.UintType(256), 31);
pub const vec_uint256_512 = ssz.FixedVectorType(ssz.UintType(256), 512);
pub const vec_uint256_513 = ssz.FixedVectorType(ssz.UintType(256), 513);

// bitlist
pub const bitlist_1 = ssz.BitListType(1);
pub const bitlist_2 = ssz.BitListType(2);
pub const bitlist_3 = ssz.BitListType(3);
pub const bitlist_4 = ssz.BitListType(4);
pub const bitlist_5 = ssz.BitListType(5);
pub const bitlist_8 = ssz.BitListType(8);
pub const bitlist_16 = ssz.BitListType(16);
pub const bitlist_31 = ssz.BitListType(31);
pub const bitlist_512 = ssz.BitListType(512);
pub const bitlist_513 = ssz.BitListType(513);

// bitvector
pub const bitvector_1 = ssz.BitVectorType(1);
pub const bitvector_2 = ssz.BitVectorType(2);
pub const bitvector_3 = ssz.BitVectorType(3);
pub const bitvector_4 = ssz.BitVectorType(4);
pub const bitvector_5 = ssz.BitVectorType(5);
pub const bitvector_8 = ssz.BitVectorType(8);
pub const bitvector_16 = ssz.BitVectorType(16);
pub const bitvector_31 = ssz.BitVectorType(31);
pub const bitvector_512 = ssz.BitVectorType(512);
pub const bitvector_513 = ssz.BitVectorType(513);

// boolean
pub const boolean = ssz.BoolType();

// containers
pub const single_field_test_struct = ssz.FixedContainerType(struct {
    A: ssz.UintType(8),
});
pub const small_test_struct = ssz.FixedContainerType(struct {
    A: ssz.UintType(16),
    B: ssz.UintType(16),
});
pub const fixed_test_struct = ssz.FixedContainerType(struct {
    A: ssz.UintType(8),
    B: ssz.UintType(64),
    C: ssz.UintType(32),
});
pub const var_test_struct = ssz.VariableContainerType(struct {
    A: ssz.UintType(16),
    B: ssz.FixedListType(ssz.UintType(16), 1024),
    C: ssz.UintType(8),
});
pub const complex_test_struct = ssz.VariableContainerType(struct {
    A: ssz.UintType(16),
    B: ssz.FixedListType(ssz.UintType(16), 128),
    C: ssz.UintType(8),
    D: ssz.ByteListType(256),
    E: var_test_struct,
    F: ssz.FixedVectorType(fixed_test_struct, 4),
    G: ssz.VariableVectorType(var_test_struct, 2),
});
pub const bits_struct = ssz.VariableContainerType(struct {
    A: ssz.BitListType(5),
    B: ssz.BitVectorType(2),
    C: ssz.BitVectorType(1),
    D: ssz.BitListType(6),
    E: ssz.BitVectorType(8),
});

// uints
pub const uint8 = ssz.UintType(8);
pub const uint16 = ssz.UintType(16);
pub const uint32 = ssz.UintType(32);
pub const uint64 = ssz.UintType(64);
pub const uint128 = ssz.UintType(128);
pub const uint256 = ssz.UintType(256);
