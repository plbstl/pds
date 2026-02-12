const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;
const assert = std.debug.assert;
const testing = std.testing;

const DEFAULT_SEED: u64 = 0x1BD45F20E4641744;
const MAX_KICKS = 500;
const MURMUR_M: u64 = 0xc6a4a7935bd1e995; // 64-bit MurmurHash2 mixing constant

const Error = error{Overflow} || Allocator.Error;

/// A space-efficient probabilistic set supporting insertion, lookup, and deletion.
///
/// False positives are possible. False negatives are not (unless insert fails).
pub fn CuckooFilter(
    comptime Fingerprint: type,
    comptime bucket_size: usize,
) type {
    assert(@typeInfo(Fingerprint) == .int);
    assert(@typeInfo(Fingerprint).int.signedness == .unsigned);

    const Bucket = [bucket_size]Fingerprint;

    return struct {
        const Self = @This();

        buckets: []Bucket,
        len: usize, // Track number of items currently in filter
        bucket_mask: usize, // Used for fast modulo (power of 2)
        hash_seed: u64,
        rng: std.Random.DefaultPrng,

        /// `expected_items` must be greater than zero.
        pub fn init(
            allocator: Allocator,
            expected_items: usize,
        ) Error!Self {
            return initWithSeed(
                allocator,
                expected_items,
                DEFAULT_SEED,
            );
        }
        /// Initializes the filter with an explicit hash seed.
        ///
        /// `expected_items` must be greater than zero.
        pub fn initWithSeed(
            allocator: Allocator,
            expected_items: usize,
            hash_seed: u64,
        ) Error!Self {
            assert(expected_items > 0);
            assert(hash_seed != 0);

            var num_buckets = (expected_items + bucket_size - 1) / bucket_size;
            num_buckets = try math.ceilPowerOfTwo(usize, num_buckets);

            const buckets = try allocator.alloc(Bucket, num_buckets);
            for (buckets) |*bucket| {
                @memset(bucket, 0);
            }

            return .{
                .buckets = buckets,
                .len = 0,
                .bucket_mask = num_buckets - 1,
                .hash_seed = hash_seed,
                .rng = std.Random.DefaultPrng.init(hash_seed),
            };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.buckets);
        }

        pub fn insert(self: *Self, item: []const u8) bool {
            const fp = self.computeFingerprint(item);

            const index1 = self.computeIndex(item);
            if (self.insertIntoBucket(index1, fp)) {
                return true;
            }

            const index2 = self.computeAltIndex(index1, fp);
            if (self.insertIntoBucket(index2, fp)) {
                return true;
            }

            // relocate existing items
            var current_fp = fp;
            var current_index = if (self.rng.random().boolean()) index1 else index2;

            for (0..MAX_KICKS) |kick| {
                // Select a slot to evict.
                // Simple optimization: cycle through slots based on kick count
                // to avoid infinite loops in local clusters.
                const slot = kick % bucket_size;

                // Swap
                const evicted_fp = self.buckets[current_index][slot];
                self.buckets[current_index][slot] = current_fp;
                current_fp = evicted_fp;

                // Calculate where the evicted item belongs
                current_index = self.computeAltIndex(current_index, current_fp);
                if (self.insertIntoBucket(current_index, current_fp)) {
                    return true;
                }
            }

            // Filter is likely too full.
            return false;
        }

        fn computeFingerprint(self: *const Self, value: []const u8) Fingerprint {
            const hash = std.hash.XxHash3.hash(self.hash_seed, value);
            const fp: Fingerprint = @truncate(hash);
            // Fingerprint 0 is reserved for empty slot
            return if (fp == 0) 1 else fp;
        }

        /// Computes the primary index (i1).
        fn computeIndex(self: *const Self, value: []const u8) usize {
            const hash = std.hash.XxHash3.hash(self.hash_seed, value);
            return @intCast(hash & self.bucket_mask);
        }

        /// Computes the secondary index (i2).
        fn computeAltIndex(self: *const Self, index1: usize, fingerprint: Fingerprint) usize {
            const fp_u64: u64 = @intCast(fingerprint);
            const h: usize = @intCast(fp_u64 *% MURMUR_M);
            return (index1 ^ h) & self.bucket_mask;
        }

        fn insertIntoBucket(self: *Self, index: usize, fingerprint: Fingerprint) bool {
            const bucket = &self.buckets[index];
            for (bucket) |*slot| {
                if (slot.* == 0) {
                    slot.* = fingerprint;
                    self.len += 1;
                    return true;
                }
            }
            return false;
        }

        pub fn contains(self: *const Self, item: []const u8) bool {
            const fp = self.computeFingerprint(item);

            const index1 = self.computeIndex(item);
            if (self.bucketHas(index1, fp)) return true;

            const index2 = self.computeAltIndex(index1, fp);
            return self.bucketHas(index2, fp);
        }

        fn bucketHas(self: *const Self, index: usize, fingerprint: Fingerprint) bool {
            inline for (0..bucket_size) |i| {
                if (self.buckets[index][i] == fingerprint) return true;
            }
            return false;
        }

        pub fn remove(self: *Self, item: []const u8) bool {
            const fp = self.computeFingerprint(item);

            const index1 = self.computeIndex(item);
            if (self.removeFromBucket(index1, fp)) {
                return true;
            }

            const index2 = self.computeAltIndex(index1, fp);
            if (self.removeFromBucket(index2, fp)) {
                return true;
            }

            return false;
        }

        fn removeFromBucket(self: *Self, index: usize, fingerprint: Fingerprint) bool {
            const bucket = &self.buckets[index];
            for (bucket) |*slot| {
                if (slot.* == fingerprint) {
                    slot.* = 0;
                    self.len -= 1;
                    return true;
                }
            }
            return false;
        }

        pub fn reset(self: *Self) void {
            for (self.buckets) |*bucket| {
                @memset(bucket, 0);
            }
            self.len = 0;
        }

        pub fn count(self: *const Self) usize {
            return self.len;
        }

        pub fn loadFactor(self: *const Self) f64 {
            const total_slots = self.buckets.len * bucket_size;
            return @as(f64, @floatFromInt(self.len)) /
                @as(f64, @floatFromInt(total_slots));
        }

        /// Returns the fingerprint for a given item.
        /// Useful for debugging or manual verification.
        pub fn getFingerprint(self: *const Self, value: []const u8) Fingerprint {
            const hash = std.hash.XxHash3.hash(self.hash_seed, value);
            const fp: Fingerprint = @truncate(hash);
            // Fingerprint 0 is reserved for empty slot
            return if (fp == 0) 1 else fp;
        }
    };
}

test "basic insert and contains" {
    const gpa = testing.allocator;

    var cf = try CuckooFilter(u8, 4).init(
        gpa,
        128,
    );
    defer cf.deinit(gpa);

    const items = [_][]const u8{
        "apple", "banana", "cherry",
    };

    for (items) |item| {
        try testing.expect(cf.insert(item));
    }

    for (items) |item| {
        try testing.expect(cf.contains(item));
    }

    try testing.expect(!cf.contains("durian"));
}

test "remove existing item" {
    const gpa = testing.allocator;

    var cf = try CuckooFilter(u8, 4).init(
        gpa,
        128,
    );
    defer cf.deinit(gpa);

    try testing.expect(cf.insert("kiwi"));
    try testing.expect(cf.contains("kiwi"));

    try testing.expect(cf.remove("kiwi"));
    try testing.expect(!cf.contains("kiwi"));
}

test "remove non-existent item" {
    const gpa = testing.allocator;

    var cf = try CuckooFilter(u8, 4).init(
        gpa,
        64,
    );
    defer cf.deinit(gpa);

    try testing.expect(!cf.remove("ghost"));
}

test "duplicate insert and remove" {
    const gpa = testing.allocator;

    var cf = try CuckooFilter(u8, 4).init(
        gpa,
        128,
    );
    defer cf.deinit(gpa);

    const item = "orange";

    try testing.expect(cf.insert(item));
    try testing.expect(cf.insert(item));

    try testing.expect(cf.contains(item));

    _ = cf.remove(item);
    // still likely present (second fingerprint)
    try testing.expect(cf.contains(item));

    _ = cf.remove(item);
    try testing.expect(!cf.contains(item));
}

test "insert failure when full" {
    const gpa = testing.allocator;

    var cf = try CuckooFilter(u8, 2).init(
        gpa,
        4, // tiny table
    );
    defer cf.deinit(gpa);

    var inserted: usize = 0;

    for (0..100) |i| {
        var buf: [16]u8 = undefined;
        const item = try std.fmt.bufPrint(&buf, "item-{d}", .{i});

        if (cf.insert(item)) {
            inserted += 1;
        } else break;
    }

    try testing.expect(inserted > 0);
    try testing.expect(inserted < 100);
}

test "getFingerprint sanity" {
    const gpa = testing.allocator;
    var cf = try CuckooFilter(u8, 4).init(
        gpa,
        32,
    );
    defer cf.deinit(gpa);

    const fp1 = cf.getFingerprint("abc");
    const fp2 = cf.getFingerprint("abc");

    try testing.expectEqual(fp1, fp2);
    try testing.expect(fp1 != 0);
}

test "different fingerprint sizes compile and work" {
    const gpa = testing.allocator;

    {
        var cf = try CuckooFilter(u8, 4).init(
            gpa,
            64,
        );
        defer cf.deinit(gpa);
        try testing.expect(cf.insert("x"));
        try testing.expect(cf.contains("x"));
    }

    {
        var cf = try CuckooFilter(u16, 4).init(
            gpa,
            64,
        );
        defer cf.deinit(gpa);
        try testing.expect(cf.insert("x"));
        try testing.expect(cf.contains("x"));
    }
}

test "capacity and resizing" {
    const gpa = testing.allocator;

    // Request capacity for 100 items
    var cf = try CuckooFilter(u8, 4).init(
        gpa,
        100,
    );
    defer cf.deinit(gpa);

    // 100 items / 4 slots = 25 buckets.
    // Nearest power of 2 is 32.
    // Total actual capacity = 32 * 4 = 128 slots.
    try testing.expectEqual(@as(usize, 32), cf.buckets.len);

    // Fill it up
    var inserted: usize = 0;
    for (0..128) |i| {
        var buf: [16]u8 = undefined;
        const key = try std.fmt.bufPrint(&buf, "key-{d}", .{i});
        if (cf.insert(key)) inserted += 1;
    }

    // Should be able to hold substantial amount (usually >90%)
    try testing.expect(inserted > 110);
}

test "reset clears buckets and length" {
    const gpa = testing.allocator;

    var cf = try CuckooFilter(u8, 4).init(
        gpa,
        32,
    );
    defer cf.deinit(gpa);

    try testing.expect(cf.insert("a"));
    try testing.expect(cf.len == 1);

    cf.reset();

    try testing.expect(cf.len == 0);
    try testing.expect(!cf.contains("a"));
}

test "load factor increases" {
    const gpa = testing.allocator;

    var cf = try CuckooFilter(u8, 4).init(
        gpa,
        32,
    );
    defer cf.deinit(gpa);

    const before = cf.loadFactor();
    try testing.expect(before == 0);

    try testing.expect(cf.insert("a"));
    try testing.expect(cf.loadFactor() > 0);
}
