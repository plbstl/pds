# PDS

Probabilistic data structures in Zig.

## Simple helper program to generate a custom seed

> This is intended for generating a compile-time constant, not for runtime use.

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
