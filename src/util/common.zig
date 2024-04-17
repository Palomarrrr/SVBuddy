const std = @import("std");

pub inline fn create(T: anytype) ![]T {
    return try std.heap.page_allocator.alloc(T, 0);
}

// TODO: Nightmare fuel redo this shit
pub inline fn splitByDelim(s: []u8, delim: u8) ![]u8 {
    var n_fields: usize = 1;
    for (s) |c| {
        if (c == delim) n_fields += 1;
    }

    var split_str: []u8 = try std.heap.page_allocator.alloc(u8, n_fields);
    var i_split: usize = 0;

    var buf = [_]u8{'0'} ** 3;
    var i_buf: u8 = 2;

    for (s, 0..s.len) |c, i| {
        if (c == delim or i == s.len - 1) {
            if (i_buf <= 2 and c != delim) { // This is janky as hell... find a better way
                buf[i_buf] = c;
                i_buf -%= 1;
            }
            split_str[i_split] = try std.fmt.parseUnsigned(u8, &buf, 10);
            i_split += 1;
            @memset(&buf, '0');
            i_buf = 2;
        } else if (c == ' ') {
            continue;
        } else {
            if (i_buf <= 2) { // This is fucking awful
                buf[i_buf] = c;
                i_buf -%= 1;
            }
        }
    }

    std.debug.print("SPLIT:{any}\n", .{split_str});
    return split_str;
}
