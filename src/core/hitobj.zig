const std = @import("std");
const math = std.math;
const time = std.time;
const heap = std.heap;
const fmt = std.fmt;
const ascii = std.ascii;
const rand = std.rand.Random;
const RAND_GEN = std.rand.DefaultPrng;

const sv = @import("./sv.zig");
const com = @import("../util/common.zig");

// Just some shorthand shit to make things easier on me
const stdout_file = std.io.getStdOut().writer();
var bw = std.io.bufferedWriter(stdout_file);
const stdout = bw.writer();

pub const HitObjError = error{
    IncompleteLine,
};

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
    objectParams: []u8,

    // fields to keep track of the shit we've done
    effects: u16 = 0,

    pub fn toStr(self: *const HitObject) ![]u8 {
        //return try std.fmt.allocPrint(std.heap.page_allocator, "{},{},{},{},{},0:0:0:0:\r\n", .{ self.x, self.y, self.time, self.type, self.hitSound });
        return try std.fmt.allocPrint(std.heap.page_allocator, "{},{},{},{},{},{s}\r\n", .{ self.x, self.y, self.time, self.type, self.hitSound, self.objectParams });
    }

    pub fn fromStr(self: *HitObject, str: []u8) !void {
        var field: u8 = 0;
        var last: usize = 0;

        //std.debug.print("FULL: `{s}`\n", .{str});
        const eol = if (ascii.indexOfIgnoreCase(str, &[_]u8{ '\r', '\n' })) |ret| ret else str.len;
        //std.debug.print("SNIPPED: `{s}`\n", .{str[0..eol]});

        while (field < 5) : (field += 1) {
            const ind = ascii.indexOfIgnoreCasePos(str, last, &[_]u8{','}) orelse return HitObjError.IncompleteLine;
            //std.debug.print("`{s}`\n", .{str[last..ind]});
            switch (field) {
                0 => {
                    self.x = try fmt.parseInt(i32, str[last..ind], 10);
                },
                1 => {
                    self.y = try fmt.parseInt(i32, str[last..ind], 10);
                },
                2 => {
                    self.time = try fmt.parseInt(i32, str[last..ind], 10);
                },
                3 => {
                    self.type = try fmt.parseUnsigned(u8, str[last..ind], 10);
                },
                4 => {
                    self.hitSound = try fmt.parseUnsigned(u8, str[last..ind], 10);
                },
                else => {
                    return HitObjError.IncompleteLine;
                },
            }
            last = ind + 1;
        }
        // THIS ISNT IMPLEMENTED YET SO WHY HAVE IT EXIST
        //std.debug.print("`{s}`\n", .{str[last..eol]});
        self.objectParams = try std.heap.page_allocator.alloc(u8, (eol - last));
        @memcpy(self.objectParams, str[last..eol]);
    }

    pub fn deinit(self: *HitObject) void {
        std.heap.page_allocator.free(self.objectParams);
    }

    // Given a NUMERIC(not a string) list of snappings and a bpm, snap to the snapping w/ the smallest difference
    pub fn snapTo(self: *HitObject, list_of_snappings: []u8, bpm: f32, bpm_offset: i32) !void {
        var diffs: []i32 = try std.heap.page_allocator.alloc(i32, list_of_snappings.len);
        var d: i32 = 9999999; // just a large number
        var d_i: usize = 0;
        const time_per_measure: f32 = 60000.0 / bpm;

        //std.debug.print("finding diffs\n", .{});
        for (list_of_snappings, 0..list_of_snappings.len) |s, i| {
            std.debug.print("i={}\n", .{i});
            const time_per_snap: f32 = time_per_measure / @as(f32, @floatFromInt(s));
            const muliplier: i32 = @intFromFloat(@round(@as(f32, @floatFromInt(self.time)) / time_per_snap));
            diffs[i] = self.time - @as(i32, @intFromFloat(@round(@as(f32, @floatFromInt(muliplier)) * time_per_snap)));
        }

        for (0..diffs.len) |i| {
            const diff: i32 = @intFromFloat(@as(f32, @sqrt(std.math.pow(f32, @as(f32, @floatFromInt(diffs[i])), 2)))); // abs(diffs[i])
            if (diff < d) {
                d = diff; // find the smallest
                d_i = i;
                //std.debug.print("new smallest {}:{}\n", .{ d, list_of_snappings[i] });
            }
        }

        //std.debug.print("NEW OFFSET: {} - {} = {}\n", .{ self.time, diffs[d_i], self.time - diffs[d_i] });
        self.time = (self.time - diffs[d_i]) + @rem(bpm_offset, @as(i32, @intFromFloat(@round(time_per_measure)))); // snap the note
    }
};

//**********************************************************
//                      UTILITIES
//**********************************************************

pub fn snapNotesTo(hitobj_array: []HitObject, snappings_str: []u8, sv_arr: []sv.TimingPoint, initial_bpm: f32, bpm_offset: i32) !void {
    const bpm: f32 = initial_bpm; // TBI

    const snappings: []u8 = try com.splitByComma(snappings_str); // Split the string
    defer std.heap.page_allocator.free(snappings);

    //const bpm_switch_time
    const n_uninherited: usize = if (sv_arr.len != 0) sv_arr.len - sv.getNumInherited(sv_arr) else 0;

    if (n_uninherited != 0) {
        std.debug.print("ERROR: Not implemented yet...\n", .{});
    } else for (0..hitobj_array.len) |i| try hitobj_array[i].snapTo(snappings, bpm, bpm_offset); // snap all notes
}

//**********************************************************
//                        EFFECTS
//**********************************************************

// So... This might be too rng to be *fully* automated....
pub fn toUnhittableNote(hitobj_array: *[]HitObject, offset: i32) !void {
    //hitobj_array.* = try std.heap.page_allocator.realloc(hitobj_array.*, hitobj_array.*.len * 2);
    var ret_array = try std.heap.page_allocator.alloc(HitObject, hitobj_array.*.len * 2);
    //defer std.heap.page_allocator.free(hitobj_array.*);

    var i: usize = 0;
    var j: usize = 0;
    while (i < hitobj_array.*.len) : (i += 2) {
        ret_array[i] = hitobj_array.*[j];
        //ret_array[i].effects = SomeValue; // <= IMPLEMENT LATER
        // ret_array[i + 1] = HitObject{ // NaN slider | Thanks Xavy
        //     .x = 256,
        //     .y = 192,
        //     .time = hitobj_array.*[j].time + offset, // I guess this might work?
        //     .type = 2,
        //     .hitSound = 8,
        //     .objectParams = @constCast("L|352:192,1,NaN,0|0,1:0|1:0,1:0:0:0:"), // Not sure if i need to place 2 or if just 1 will do
        // };
        //256,192,674,6,4,L|352:192,1,NaN | From Mew
        // Other taken from xavy

        // TODO: Remove this awful janky fix... Find a fucking better way
        // For some god-forsaken reason the approach above doesn't work and I'm forced to do this bs
        try ret_array[i + 1].fromStr(@constCast("256,192,0,2,8,L|352:192,1,NaN,0|0,1:0|1:0,1:0:0:0:\r\n"));
        ret_array[i + 1].time = hitobj_array.*[j].time + offset;
        j += 1;
    }

    hitobj_array.* = ret_array;
}

// Need this to return a slice instead of an array. either that or i need to find a good way to turn the result into a slice
pub fn toBarline(hitobj_array: []HitObject) ![]sv.TimingPoint {
    const timing_points: []sv.TimingPoint = try std.heap.page_allocator.alloc(sv.TimingPoint, hitobj_array.len);
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
