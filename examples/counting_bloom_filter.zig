const std = @import("std");
const CountingBloomFilter = @import("pds").CountingBloomFilter;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // Create a counting Bloom filter:
    // - expected 100 items
    // - 1% false positive rate
    // - u8 counters
    var filter = try CountingBloomFilter(u8).init(
        allocator,
        100,
        0.01,
    );
    defer filter.deinit(allocator);

    std.debug.print("Counting Bloom Filter example\n\n", .{});

    const fruits = [_][]const u8{
        "apple",
        "banana",
        "cherry",
    };

    // Add items
    for (fruits) |fruit| {
        filter.add(fruit);
        std.debug.print("Added: {s}\n", .{fruit});
    }

    std.debug.print("\nMembership checks:\n", .{});

    // Check inserted items
    for (fruits) |fruit| {
        const exists = filter.contains(fruit);
        std.debug.print("  {s}: {any}\n", .{ fruit, exists });
    }

    // Check a non-inserted item
    const unknown = "grape";
    std.debug.print("  {s}: {any}\n", .{
        unknown,
        filter.contains(unknown),
    });

    // Demonstrate removal
    std.debug.print("\nRemoving banana...\n", .{});
    filter.remove("banana");

    std.debug.print("  banana: {any}\n", .{
        filter.contains("banana"),
    });

    // Demonstrate reset
    std.debug.print("\nResetting filter...\n", .{});
    filter.reset();

    for (fruits) |fruit| {
        std.debug.print("  {s}: {any}\n", .{
            fruit,
            filter.contains(fruit),
        });
    }
}
