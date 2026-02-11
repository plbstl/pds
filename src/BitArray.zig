const BitArray = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const testing = std.testing;

const Word = usize;

len: usize,
words: []Word,

pub fn init(allocator: Allocator, length: usize) Allocator.Error!BitArray {
    assert(length > 0);
    const word_bits = @bitSizeOf(Word);
    const word_count = (length + word_bits - 1) / word_bits;

    const words = try allocator.alloc(Word, word_count);
    @memset(words, 0);

    return .{
        .len = length,
        .words = words,
    };
}

pub fn deinit(self: *BitArray, allocator: Allocator) void {
    allocator.free(self.words);
}

pub fn set(self: *BitArray, index: usize) void {
    assert(index < self.len);
    const word_bits = @bitSizeOf(Word);
    const word = index / word_bits;
    const bit = index % word_bits;
    self.words[word] |= @as(Word, 1) << @intCast(bit);
}

pub fn unset(self: *BitArray, index: usize) void {
    assert(index < self.len);
    const word_bits = @bitSizeOf(Word);
    const word = index / word_bits;
    const bit = index % word_bits;
    self.words[word] &= ~(@as(Word, 1) << @intCast(bit));
}

pub fn isSet(self: *const BitArray, index: usize) bool {
    assert(index < self.len);
    const word_bits = @bitSizeOf(Word);
    const word = index / word_bits;
    const bit = index % word_bits;
    return (self.words[word] & (@as(Word, 1) << @intCast(bit))) != 0;
}

pub fn unsetAll(self: *BitArray) void {
    @memset(self.words, 0);
}

test "set and get bit" {
    const gpa = testing.allocator;
    var ba = try BitArray.init(gpa, 128);
    defer ba.deinit(gpa);

    ba.set(0);
    ba.set(65);
    ba.set(127);

    try testing.expect(ba.isSet(0));
    try testing.expect(ba.isSet(65));
    try testing.expect(ba.isSet(127));

    try testing.expect(!ba.isSet(31));
}

test "unset bit" {
    const gpa = testing.allocator;
    var ba = try BitArray.init(gpa, 64);
    defer ba.deinit(gpa);

    ba.set(3);
    try testing.expect(ba.isSet(3));

    ba.unset(3);
    try testing.expect(!ba.isSet(3));
}
