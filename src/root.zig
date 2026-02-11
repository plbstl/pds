//! Probabilistic data structures for approximate queries on large or
//! streaming data. These structures trade exactness for speed and
//! memory efficiency.
//!

pub const BloomFilter = @import("BloomFilter.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
