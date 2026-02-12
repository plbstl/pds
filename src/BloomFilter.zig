//! Probabilistic set for fast membership tests.
//!
//! False negatives are not possible, but may return false
//! positives. Items cannot be removed once inserted.

const BloomFilter = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const ln2 = std.math.ln2;
const testing = std.testing;
const BitArray = @import("BitArray.zig");

bits: BitArray,
hash_seed: u64,
indexes_per_item: usize,

const DEFAULT_SEED: u64 = 0x1BD45F20E4641744;

const HashPair = struct {
    hash1: u32,
    hash2: u32,
};

/// `expected_items` must be greater than zero.
///
/// `error_rate` must be between 0.0 and 1.0 (exclusive), e.g. 0.01 for 1%.
pub fn init(
    allocator: Allocator,
    expected_items: usize,
    error_rate: f64,
) Allocator.Error!BloomFilter {
    return initWithSeed(
        allocator,
        expected_items,
        error_rate,
        DEFAULT_SEED,
    );
}

/// Initializes the filter with an explicit hash seed.
///
/// `expected_items` must be greater than zero.
///
/// `error_rate` must be between 0.0 and 1.0 (exclusive), e.g. 0.01 for 1%.
pub fn initWithSeed(
    allocator: Allocator,
    expected_items: usize,
    error_rate: f64,
    hash_seed: u64,
) Allocator.Error!BloomFilter {
    assert(expected_items > 0);
    assert(error_rate > 0 and error_rate < 1);
    assert(hash_seed != 0);

    const m = computeCappedTotalNumberOfBits(expected_items, error_rate);
    const bits = try BitArray.init(allocator, m);
    const k = computeNumberOfIndexesPerItem(error_rate);

    return .{
        .bits = bits,
        .hash_seed = hash_seed,
        .indexes_per_item = k,
    };
}

fn computeCappedTotalNumberOfBits(n: usize, p: f64) usize {
    // m = -(n * ln(p)) / (ln(2)^2)
    const n_float: f64 = @floatFromInt(n);
    const m = -(n_float * @log(p)) / (ln2 * ln2);
    return @intFromFloat(@ceil(m));
}

fn computeNumberOfIndexesPerItem(p: f64) usize {
    // k = -log2(p)
    const k = -@log2(p);
    return @max(1, @as(usize, @intFromFloat(@ceil(k))));
}

pub fn deinit(self: *BloomFilter, allocator: Allocator) void {
    self.bits.deinit(allocator);
}

/// Adds an item to the set.
pub fn add(self: *BloomFilter, item: []const u8) void {
    const hashes = computeHashPair(self.hash_seed, item);
    for (0..self.indexes_per_item) |i| {
        const index = computeIndex(
            hashes.hash1,
            hashes.hash2,
            i,
            self.bits.len,
        );
        self.bits.set(index);
    }
}

/// Checks if an item is likely in the set.
pub fn contains(self: *const BloomFilter, item: []const u8) bool {
    const hashes = computeHashPair(self.hash_seed, item);
    for (0..self.indexes_per_item) |i| {
        const index = computeIndex(
            hashes.hash1,
            hashes.hash2,
            i,
            self.bits.len,
        );
        if (!self.bits.isSet(index)) {
            return false;
        }
    }

    return true;
}

fn computeHashPair(seed: u64, value: []const u8) HashPair {
    const hash = std.hash.XxHash3.hash(seed, value);
    const h1: u32 = @truncate(hash);
    const h2: u32 = @truncate(hash >> 32);
    return .{
        .hash1 = h1,
        .hash2 = h2 | 1,
    };
}

fn computeIndex(hash1: u32, hash2: u32, i: usize, m: usize) usize {
    // index_i = (h1 + i * h2) mod m
    const combined: u64 = hash1 +% i *% hash2;
    return @intCast(combined % m);
}

/// Resets all bits to zero. Keeps allocated memory and config.
pub fn reset(self: *BloomFilter) void {
    self.bits.unsetAll();
}

pub fn bitSize(self: *const BloomFilter) usize {
    return self.bits.len;
}

pub fn numHashesPerItem(self: *const BloomFilter) usize {
    return self.indexes_per_item;
}

test "no false negatives" {
    const gpa = testing.allocator;

    var bf = try BloomFilter.init(gpa, 10, 0.01);
    defer bf.deinit(gpa);

    const fruits = [_][]const u8{
        "apple", "banana", "cherry", "date", "elderberry", "fig", "guava",
    };

    for (fruits) |fruit| {
        bf.add(fruit);
    }

    for (fruits) |fruit| {
        try testing.expect(bf.contains(fruit));
    }
}

test "empty filter returns false" {
    const gpa = testing.allocator;
    var bf = try BloomFilter.init(gpa, 450, 0.01);
    defer bf.deinit(gpa);

    try testing.expect(!bf.contains("not-present"));
}

test "reset entries" {
    const gpa = testing.allocator;

    var bf = try BloomFilter.init(gpa, 5_000, 0.01);
    defer bf.deinit(gpa);

    const value = "22";

    bf.add(value);
    try testing.expect(bf.contains(value));

    bf.reset();
    try testing.expect(!bf.contains(value));
}

test "sizing: m and k are sane" {
    const n = 10_000;
    const p = 0.02;

    const m = computeCappedTotalNumberOfBits(n, p);
    const k = computeNumberOfIndexesPerItem(p);

    try testing.expect(m > n);
    try testing.expect(k >= 1);
    try testing.expect(k <= 8); // practical upper bound
}

test "sizing: lower error rate increases m" {
    const n = 8000;

    const m1 = computeCappedTotalNumberOfBits(n, 0.1);
    const m2 = computeCappedTotalNumberOfBits(n, 0.01);
    const m3 = computeCappedTotalNumberOfBits(n, 0.001);

    try testing.expect(m1 < m2);
    try testing.expect(m2 < m3);
}

test "sizing: more items increases m" {
    const p = 0.05;

    const m1 = computeCappedTotalNumberOfBits(100, p);
    const m2 = computeCappedTotalNumberOfBits(1_000, p);
    const m3 = computeCappedTotalNumberOfBits(10_000, p);

    try testing.expect(m1 < m2);
    try testing.expect(m2 < m3);
}
