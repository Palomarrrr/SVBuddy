const std = @import("std");

pub const CommonError = error{
    NonNumericInput,
    InvalidInput,
};

pub inline fn create(T: anytype) ![]T {
    return try std.heap.page_allocator.alloc(T, 0);
}

// TODO: Nightmare fuel redo this shit
pub inline fn splitByComma(s: []u8) ![]u8 {
    var n_fields: usize = 1;
    for (s) |c| { // count up how many u8s to alloc
        switch (c) {
            ',' => n_fields += 1,
            else => continue,
        }
    }

    var split_str: []u8 = try std.heap.page_allocator.alloc(u8, n_fields);
    var i_split: usize = 0;

    var buf = [_]u8{'0'} ** 3;
    var i_buf: u8 = 0;

    for (s, 0..s.len) |c, i| {
        _ = i;
        switch (c) {
            ',' => {
                split_str[i_split] = std.fmt.parseUnsigned(u8, buf[0..i_buf], 10) catch |e| {
                    std.heap.page_allocator.free(split_str);
                    return e;
                };
                i_split += 1;
                @memset(&buf, '0');
                i_buf = 0;
            },
            '0'...'9' => {
                if (i_buf < 3) {
                    buf[i_buf] = c;
                    i_buf += 1;
                } else {
                    std.heap.page_allocator.free(split_str);
                    return CommonError.InvalidInput;
                }
            },
            ' ' => continue,
            else => {
                std.heap.page_allocator.free(split_str);
                return CommonError.NonNumericInput;
            },
        }
    }
    if (i_buf != 0) { // if != 0 then there must be something in the buffer
        split_str[i_split] = std.fmt.parseUnsigned(u8, buf[0..i_buf], 10) catch |e| {
            std.heap.page_allocator.free(split_str);
            return e;
        };
    }

    return split_str;
}
