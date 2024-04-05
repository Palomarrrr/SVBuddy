const std = @import("std");

pub inline fn create(T: anytype) ![]T {
    return try std.heap.raw_c_allocator.alloc(T, 0);
}
