const std = @import("std");

pub inline fn create(T: anytype) ![]T {
    return try std.heap.page_allocator.alloc(T, 0);
}
