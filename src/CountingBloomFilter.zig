//! A Bloom filter variant that supports deletion.
//!

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const math = std.math;
const testing = std.testing;

const DEFAULT_SEED: u64 = 0x1BD45F20E4641744;

const HashPair = struct {
    hash1: u32,
    hash2: u32,
};

/// A Bloom filter variant that supports deletion.
pub fn CountingBloomFilter(comptime Counter: type) type {
    return struct {
        const Self = @This();

        counters: []Counter,
        hash_seed: u64,
        indexes_per_item: usize,

        /// `expected_items` must be greater than zero.
        ///
        /// `error_rate` must be between 0.0 and 1.0 (exclusive), e.g. 0.01 for 1%.
        pub fn init(
            allocator: Allocator,
            expected_items: usize,
            error_rate: f64,
        ) Allocator.Error!Self {
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
        ) Allocator.Error!Self {
            assert(@typeInfo(Counter) == .int);
            assert(@typeInfo(Counter).int.signedness == .unsigned);
            assert(expected_items > 0);
            assert(error_rate > 0 and error_rate < 1);
            assert(hash_seed != 0);

            const m = computeCappedTotalNumberOfBits(expected_items, error_rate);
            const k = computeNumberOfIndexesPerItem(error_rate);

            const counters = try allocator.alloc(Counter, m);
            @memset(counters, 0);

            return .{
                .counters = counters,
                .hash_seed = hash_seed,
                .indexes_per_item = k,
            };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.counters);
        }

        /// Adds an item to the set.
        pub fn add(self: *Self, item: []const u8) void {
            const hashes = computeHashPair(self.hash_seed, item);
            for (0..self.indexes_per_item) |i| {
                const index = computeIndex(
                    hashes.hash1,
                    hashes.hash2,
                    i,
                    self.counters.len,
                );

                if (self.counters[index] < math.maxInt(Counter)) {
                    self.counters[index] += 1;
                }
            }
        }

        /// Removes an item from the set.
        pub fn remove(self: *Self, item: []const u8) void {
            const hashes = computeHashPair(self.hash_seed, item);
            for (0..self.indexes_per_item) |i| {
                const index = computeIndex(
                    hashes.hash1,
                    hashes.hash2,
                    i,
                    self.counters.len,
                );
                if (self.counters[index] > 0) {
                    self.counters[index] -= 1;
                }
            }
        }

        /// Checks if an item is likely in the set.
        pub fn contains(self: *const Self, item: []const u8) bool {
            const hashes = computeHashPair(self.hash_seed, item);
            for (0..self.indexes_per_item) |i| {
                const index = computeIndex(
                    hashes.hash1,
                    hashes.hash2,
                    i,
                    self.counters.len,
                );
                if (self.counters[index] == 0) {
                    return false;
                }
            }

            return true;
        }

        /// Reset counters to zero. Keeps allocated memory and config.
        pub fn reset(self: *Self) void {
            @memset(self.counters, 0);
        }
    };
}

fn computeCappedTotalNumberOfBits(n: usize, p: f64) usize {
    // m = -(n * ln(p)) / (ln(2)^2)
    const n_float: f64 = @floatFromInt(n);
    const m = -(n_float * @log(p)) / (math.ln2 * math.ln2);
    return @intFromFloat(@ceil(m));
}

fn computeNumberOfIndexesPerItem(p: f64) usize {
    // k = -log2(p)
    const k = -@log2(p);
    return @max(1, @as(usize, @intFromFloat(@ceil(k))));
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

test "basic add/remove" {
    const gpa = testing.allocator;

    var cbf = try CountingBloomFilter(u4).init(
        gpa,
        10,
        0.01,
    );
    defer cbf.deinit(gpa);

    const items = [_][]const u8{
        "apple", "banana", "cherry",
    };

    for (items) |item| cbf.add(item);
    for (items) |item| try testing.expect(cbf.contains(item));

    cbf.remove("banana");
    try testing.expect(!cbf.contains("banana"));

    // others unaffected
    try testing.expect(cbf.contains("apple"));
    try testing.expect(cbf.contains("cherry"));
}

test "duplicate insert requires duplicate remove" {
    const gpa = testing.allocator;

    var cbf = try CountingBloomFilter(u8).init(
        gpa,
        10,
        0.01,
    );
    defer cbf.deinit(gpa);

    const item = "orange";

    cbf.add(item);
    cbf.add(item);

    try testing.expect(cbf.contains(item));

    cbf.remove(item);
    // should still exist (one reference left)
    try testing.expect(cbf.contains(item));

    cbf.remove(item);
    try testing.expect(!cbf.contains(item));
}

test "remove non-existent does not underflow" {
    const gpa = testing.allocator;

    var cbf = try CountingBloomFilter(u4).init(
        gpa,
        10,
        0.01,
    );
    defer cbf.deinit(gpa);

    cbf.remove("ghost");
    try testing.expect(!cbf.contains("ghost"));
}

test "counter saturates at maxInt" {
    const gpa = testing.allocator;

    var cbf = try CountingBloomFilter(u4).init(
        gpa,
        1,
        0.01,
    );
    defer cbf.deinit(gpa);

    const item = "a";

    // add more times than u4 can represent
    for (0..20) |_| {
        cbf.add(item);
    }

    // remove same number of times
    for (0..20) |_| {
        cbf.remove(item);
    }

    // should not wrap negative; should just be gone
    try testing.expect(!cbf.contains(item));
}

test "reset clears all counters" {
    const gpa = testing.allocator;

    var cbf = try CountingBloomFilter(u8).init(
        gpa,
        10,
        0.01,
    );
    defer cbf.deinit(gpa);

    cbf.add("alpha");
    cbf.add("beta");

    try testing.expect(cbf.contains("alpha"));
    try testing.expect(cbf.contains("beta"));

    cbf.reset();

    try testing.expect(!cbf.contains("alpha"));
    try testing.expect(!cbf.contains("beta"));
}

test "works with different counter types" {
    const gpa = testing.allocator;

    {
        var cbf = try CountingBloomFilter(u8).init(gpa, 10, 0.01);
        defer cbf.deinit(gpa);
        cbf.add("x");
        try testing.expect(cbf.contains("x"));
    }

    {
        var cbf = try CountingBloomFilter(u16).init(gpa, 10, 0.01);
        defer cbf.deinit(gpa);
        cbf.add("x");
        try testing.expect(cbf.contains("x"));
    }
}

test "basic false positive sanity" {
    const gpa = testing.allocator;

    var cbf = try CountingBloomFilter(u8).init(
        gpa,
        100,
        0.01,
    );
    defer cbf.deinit(gpa);

    const inserted = [_][]const u8{
        "a", "b", "c", "d", "e",
    };

    for (inserted) |item| cbf.add(item);

    // unlikely to all be false positives
    try testing.expect(!cbf.contains("not-inserted-1"));
    try testing.expect(!cbf.contains("not-inserted-2"));
}
