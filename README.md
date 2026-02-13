# PDS

Probabilistic data structures written in Zig.

- BloomFilter
- CountingBloomFilter
- CuckooFilter

## Examples

Build and run examples with `zig build <example_name> [-Drun]`. For example:

```bash
zig build bloom_filter # build binary to zig-out
zig build cuckoo_filter -Drun # build binary and also run the program
```

## Simple helper program to generate a custom seed

> Generate compile-time constant. Not for runtime use.

Run `zig init` in an empty folder and replace `src/main.zig` with this:

```zig
const std = @import("std");
pub fn main(init: std.process.Init) void {
    const now = std.Io.Timestamp.now(init.io, .real).nanoseconds;

    var prng = std.Random.DefaultPrng.init(@intCast(now));
    const r = prng.random();
    const seed = r.int(u64);

    std.debug.print("0x{X:0>16}\n", .{seed});
}
```

Run `zig build run`.
