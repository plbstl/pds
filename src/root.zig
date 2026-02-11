//! Probabilistic data structures for approximate queries on large or
//! streaming data. These structures trade exactness for speed and
//! memory efficiency.
//!

pub const BloomFilter = @import("BloomFilter.zig");
pub const CountingBloomFilter = @import("CountingBloomFilter.zig").CountingBloomFilter;

test {
    @import("std").testing.refAllDecls(@This());
}
