const std = @import("std");
const CuckooFilter = @import("pds").CuckooFilter;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var filter = try CuckooFilter(u8, 4).init(
        allocator,
        800,
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
        _ = filter.insert(fruit);
        std.debug.print("Inserted: {s}\n", .{fruit});
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

    // Remove items
    std.debug.print("\nRemoving banana...\n", .{});
    _ = filter.remove("banana");

    std.debug.print("  banana: {any}\n", .{
        filter.contains("banana"),
    });

    // Reset filter
    std.debug.print("\nResetting filter...\n", .{});
    filter.reset();

    for (fruits) |fruit| {
        std.debug.print("  {s}: {any}\n", .{
            fruit,
            filter.contains(fruit),
        });
    }
}
