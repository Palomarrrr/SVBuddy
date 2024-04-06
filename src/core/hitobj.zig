const std = @import("std");
const math = std.math;
const time = std.time;
const heap = std.heap;
const fmt = std.fmt;
const rand = std.rand.Random;
const RAND_GEN = std.rand.DefaultPrng;

const sv = @import("./libsv.zig");

// Just some shorthand shit to make things easier on me
const stdout_file = std.io.getStdOut().writer();
var bw = std.io.bufferedWriter(stdout_file);
const stdout = bw.writer();

//**********************************************************
//                        STRUCTS
//**********************************************************

pub const HitObject = struct {
    // fields for osu's parameters
    x: i32 = 0,
    y: i32 = 0,
    time: i32 = 0,
    type: u8 = 0,
    hitSound: u8 = 0,
    objectParams: [200]u8 = undefined, // I'm guessing ill just make this a string and store the field like that since the formatting is fucked

    // fields to keep track of the shit we've done
    effects: u16 = 0,

    pub fn toStr(self: *const HitObject) ![]u8 {
        //return try std.fmt.allocPrint(heap.raw_c_allocator, "{},{},{},{},{},0:0:0:0:\r\n", .{ self.x, self.y, self.time, self.type, self.hitSound });
        return try std.fmt.allocPrint(heap.raw_c_allocator, "{},{},{},{},{},end\r\n", .{ self.x, self.y, self.time, self.type, self.hitSound });
    }
};

//**********************************************************
//                        EFFECTS
//**********************************************************

// TODO - Create more and implement

// Need this to return a slice instead of an array. either that or i need to find a good way to turn the result into a slice
pub fn toBarline(hitobj_array: []HitObject) ![]sv.TimingPoint {
    const timing_points: []sv.TimingPoint = try heap.raw_c_allocator.alloc(sv.TimingPoint, hitobj_array.len);
    for (0..hitobj_array.len) |i| {
        if ((hitobj_array[i].type & 0x1) != 1) continue; // Skip non-notes

        if ((hitobj_array[i].hitSound & 0x1) == 1) { // NEED TO ALSO CHECK FOR FINISHER D
            // D

            // Place a barline on the note with "omit first barline" enabled
            // Place a 10x sv point on the note
            // Place a barline 1ms before the note (WITH THE PROPER SV FOR THE SECTION)
            // Place a sv point 1ms after the note with the proper sv for the section

        } else {
            // K

            // Place a barline on the note with "omit first barline" enabled
            // Place a 10x sv point on the note
            // Place 4 barlines 4ms, 3ms, 2ms, and 1ms before the note (ALL WITH THE PROPER SV FOR THE SECTION)
            // Place a sv point 1ms after the note with the proper sv for the section
            //barlines[i].time = hitobj_array[i].time - 4
            //barlines[i].time = hitobj_array[i].time - 3
            //barlines[i].time = hitobj_array[i].time - 2
            //barlines[i].time = hitobj_array[i].time - 1
            //barlines[i].time = hitobj_array[i].time - 4
            //barlines[i].time = hitobj_array[i].time - 4

        }
    }
    return timing_points;
}
