const std = @import("std");
const BloomFilter = @import("pds").BloomFilter;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var bf = try BloomFilter.init(
        allocator,
        20_000,
        0.01,
    );
    defer bf.deinit(allocator);

    // total number of bits
    std.debug.print("Number of bits: {}\n", .{bf.bitSize()});
    std.debug.print("Hashes per item: {}\n\n", .{bf.numHashesPerItem()});

    // hello world
    const hello_world = "hello world";

    // add hello world
    bf.add(hello_world);

    // check if hello world has been (likely) added
    const has_hello_world = bf.contains(hello_world);

    // print out the result
    std.debug.print("{s}: {}\n\n", .{ hello_world, has_hello_world });

    // check for a value that wasn't added
    std.debug.print("{s}: {}\n\n", .{ "added", bf.contains("added") });

    // binary data
    const byte_value = std.mem.toBytes(@as(u32, 42));
    bf.add(&byte_value);
    std.debug.print("byte_value: {}\n\n", .{bf.contains(&byte_value)});

    // reset
    bf.reset();
    // previously saved value is not set anymore
    std.debug.print("{s}: {}\n", .{ hello_world, bf.contains(hello_world) });
}
