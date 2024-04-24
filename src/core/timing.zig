const std = @import("std");
const sv = @import("sv.zig");

const TimingErr = error{
    InvalidChar,
};

// This should handle all things to do with timing adjustments, timestrtotick, resnapping, you get the gist
pub fn timeStrToTick(time_str: []u8) !i32 {
    var time: i32 = 0;
    var tbit: i32 = 0;
    var i: u2 = 0;

    // TODO: i feel like this can be done with one var
    for (time_str) |c| {
        switch (c) {
            ':', ';' => {
                switch (i) {
                    0 => tbit *= 60000,
                    1 => tbit *= 1000,
                    else => break,
                }
                time += tbit;
                tbit = 0;
                i += 1;
            },
            '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
                tbit *= 10;
                tbit += (c - '0');
            },
            else => return TimingErr.InvalidChar,
        }
    }

    return time + tbit;
}
