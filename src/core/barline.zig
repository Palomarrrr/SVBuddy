const std = @import("std");
const sv = @import("./sv.zig");
const osufile = @import("./osufileio.zig");
const com = @import("../util/common.zig");

pub const BarlineError = error{
    InvalidTimeRange,
};

// TODO: Make this work better w/ other horizontal res | THIS NUMBER (the constant 460 in there) SEEMS COMPLETELY ARBITRARY IM KILLING MYSELF
pub inline fn pxDistToSV(px: f32, target_hres: f32) f32 { // This also works w/ nLinesOnScreenToSV
    return target_hres / (px * 460);
}

inline fn randomBPMBarline(time: i32, min_bpm: f32, max_bpm: f32, rand: std.Random) sv.TimingPoint {
    const dist_bpm = max_bpm - min_bpm;
    const next_bpm: f32 = (dist_bpm * std.Random.float(rand, f32)) + min_bpm;

    return sv.TimingPoint{
        .time = time,
        .value = 60000.0 / next_bpm,
        .meter = 255,
        .volume = 100,
        .is_inh = 1,
        .sample_set = 0,
        .effects = 0,
    };
}

// Generates between two static bounds
pub fn staticRandomBarlines(start_bpm: f32, start_time: i32, end_time: i32, percent_chance: u8, min_bpm: f32, max_bpm: f32) ![]sv.TimingPoint {
    var tp = try std.heap.page_allocator.alloc(sv.TimingPoint, 1); // This is going to be fucking awful
    tp[0] = sv.TimingPoint{ // Make an initial point
        .time = start_time,
        .value = (60000.0 / ((max_bpm + min_bpm) / 2)),
        .meter = 255,
        .volume = 100,
        .is_inh = 1,
        .sample_set = 0,
        .effects = 0,
    };

    const dist_time: u32 = @intCast(end_time - start_time);
    var rand = std.Random.Pcg.init(@intCast(std.time.timestamp()));
    for (0..dist_time) |t| {
        const line_roll: u8 = std.Random.uintAtMost(rand.random(), u8, 100);
        if (line_roll <= percent_chance) {
            tp = try std.heap.page_allocator.realloc(tp, tp.len + 1);
            tp[tp.len - 1] = randomBPMBarline(start_time + @as(i32, @intCast(t)), min_bpm, max_bpm, rand.random());
        }
    }

    // Create a cap on the end to make sure this isn't fucking up things after the section
    tp = try std.heap.page_allocator.realloc(tp, tp.len + 1);
    tp[0] = sv.TimingPoint{ // Make an initial point
        .time = end_time,
        .value = (60000 / start_bpm),
        .meter = 4,
        .volume = 100,
        .is_inh = 1,
        .sample_set = 0,
        .effects = 0,
    };

    return tp;
}

// TODO: create
// TLDR - create a line between the two mins, and two maxes, then randomly generate values bounded between those lines
// pub fn linearRandomBarlines(start_bpm: f32, start_time: i32, end_time: i32, percent_chance: u8, start_min_bpm: f32, start_max_bpm: f32, end_min_bpm: f32, end_max_bpm: f32) ![]sv.TimingPoint {
// }

// Just to reduce some repetitive shit
// This might introduce more problems than not since id have to move the contents of tp[1] to the end of whatever im generating
pub fn create60kSection(start_bpm: f32, start_time: i32, end_time: i32, opts: u8) ![]sv.TimingPoint { // This returns an optional somehow??
    var tp = try std.heap.page_allocator.alloc(sv.TimingPoint, 2);
    tp[0] = sv.TimingPoint{ // Make an initial point
        .time = start_time,
        .value = 1,
        .meter = 1,
        .volume = 100,
        .is_inh = 1,
        .sample_set = 0,
        .effects = 0,
    };
    tp[1] = sv.TimingPoint{ // Make the ending point
        .time = end_time,
        .value = (60000 / start_bpm),
        .meter = 4,
        .volume = 100,
        .is_inh = 1,
        .sample_set = 0,
        .effects = if (opts & 0x2 == 0x2) 0x8 else 0x0, // 0x8 should be omit first barline
    };
    return tp; // Thats kinda it...
}

pub fn static60kBarline(sv_arr: *[]sv.TimingPoint, time: i32, bl_dist: f32, target_hres: f32) !void {
    sv_arr.* = try std.heap.page_allocator.realloc(sv_arr.*, sv_arr.*.len + 1); // Allocate for new points
    sv_arr.*[sv_arr.*.len - 1] = sv_arr.*[sv_arr.*.len - 2]; // Move the end back

    // Im pretty sure this potentially not being sorted shouldnt cause any problems... but im not 100% sure
    sv_arr.*[sv_arr.*.len - 2] = sv.TimingPoint{
        .time = time,
        .value = -100 / pxDistToSV(bl_dist, target_hres),
        .is_inh = 0,
    };

    if (time < sv_arr.*[0].time) { // If before sv_arr's start time
        sv_arr.*[0].time = time;
    } else if (time > sv_arr.*[sv_arr.*.len - 1].time) { // If after sv_arr's end time
        sv_arr.*[sv_arr.*.len - 1].time = time;
    }
    // That should be it???
}

// IDEA:
// Make an entire barline effect editor with lines on screen (sv) transitions
// and barline frequency (meter) transitions as well as some other stuff

// Workflow of the barline editor
// ==============================
// 1. create a 60k section
// 2. make effects in that section that either span the entire section or portions of it
//      - all of these will be written to the file individually which could be kinda expensive but allows for individual bits to be undone
//      - This should also probably concatinate 60k sections if they are placed one after another (i.e. section A ends on tick 123 and section B picks up on tick 123) (also should probably be a toggle just in case)
// I feel like all of these should be done through some kind of wrapper fn that takes all the params it needs and splits it up into different fns

// TODO: There should be a check before these functions are called that makes sure that these are in a 60k section beforehand | maybe not?
pub fn linear60kBarline(sv_arr: *[]sv.TimingPoint, bl_start: f32, bl_end: f32, target_hres: f32, effect_snapping: u8) !void { // Consider finding a more consistent way of getting the point increment because doing it off the initial bpm is a little fucky
    var curr_bl: f32 = bl_start;
    var curr_time: i32 = sv_arr.*[0].time;
    const inc: i32 = @as(i32, @intFromFloat(sv_arr.*[sv_arr.*.len - 1].value / @as(f32, @floatFromInt(effect_snapping)))); // This is producing zero for some reason
    std.debug.print("inc:{},snap:{},value:{}\n", .{ inc, effect_snapping, sv_arr.*[sv_arr.*.len - 1].value });
    const n_pts: u32 = @intCast(@divTrunc((sv_arr.*[sv_arr.*.len - 1].time - sv_arr.*[0].time), inc));
    const bl_slope = ((bl_end - bl_start) / @as(f32, @floatFromInt(n_pts)));

    sv_arr.* = try std.heap.page_allocator.realloc(sv_arr.*, n_pts + 2);

    sv_arr.*[sv_arr.*.len - 1] = sv_arr.*[1]; // Im just going to go ahead and assume that this is where the end point is

    // Linear progression
    for (1..sv_arr.*.len - 1) |i| {
        sv_arr.*[i] = sv.TimingPoint{ // Make an initial point
            .time = curr_time,
            .value = -100.0 / pxDistToSV(curr_bl, target_hres),
            .meter = 1,
            .volume = 100,
            .is_inh = 0,
            .sample_set = 0,
            .effects = 0,
        };
        curr_bl += bl_slope;
        curr_time += inc;
    }
}

// TODO: This is very inefficient as it creates another array, fills it, and then merges it...
pub fn linear60kMeter(sv_arr: *[]sv.TimingPoint, meter_start: u16, meter_end: u16) !void {
    // Do not generate on redlines or on greenlines that are on the same tick as redlines
    // First thing to do is count up all inherited points
    // We cant use getNumInherited since it includes points that exist on redlines

    var n_pts: usize = 1; // trust that the first point is good
    var n_existing_60ks: usize = if (sv_arr.*[0].is_inh == 1 and sv_arr.*[0].value == 1) 1 else 0; // check if first point is 60k
    for (1..sv_arr.*.len) |i| {
        if (sv_arr.*[i].is_inh == 1) { // If redline
            if (sv_arr.*[i].value == 1) { // if 60k point
                n_existing_60ks += 1;
                if (sv_arr.*[i - 1].time != sv_arr.*[i].time) n_pts += 1; // If no point exists on it
            } else { // if not 60k
                //removed `sv_arr.*[i - 1].is_inh == 0 and` as i dont really think its needed?
                if (sv_arr.*[i - 1].time == sv_arr.*[i].time and n_pts != 0) n_pts -= 1; // if has attached inh point
            }
        } else { // If greenline
            if (sv_arr.*[i - 1].time != sv_arr.*[i].time) n_pts += 1; // If no point exists on it
        }
    }
    std.debug.print("n_pts: {}\n", .{n_pts});

    const meter_slope: f32 = (@as(f32, @floatFromInt(meter_end)) - @as(f32, @floatFromInt(meter_start))) / @as(f32, @floatFromInt(sv_arr.*[sv_arr.*.len - 2].time - sv_arr.*[0].time)); // Potentially dangerous

    if (n_existing_60ks != 0) {
        for (sv_arr.*.len, 0..) |_, i| {
            if (sv_arr.*[i].is_inh == 1 and sv_arr.*[i].value == 1) {
                sv_arr.*[i].meter = @as(u16, @intFromFloat((meter_slope * @as(f32, @floatFromInt(sv_arr.*[i].time - sv_arr.*[0].time))) + @as(f32, @floatFromInt(meter_start))));
                std.debug.print("made meter: {}\n", .{sv_arr.*[i].meter});
                std.debug.print("{d:.2} * {} - {} = {d:.2}\n", .{ meter_slope, sv_arr.*[i].time, sv_arr.*[0].time, (meter_slope * @as(f32, @floatFromInt(sv_arr.*[i].time - sv_arr.*[0].time))) });
                std.debug.print("{d:.2} + {} = {d:.2} -> {}\n", .{ (meter_slope * @as(f32, @floatFromInt(sv_arr.*[i].time - sv_arr.*[0].time))), meter_start, (meter_slope * @as(f32, @floatFromInt(sv_arr.*[i].time - sv_arr.*[0].time))) + @as(f32, @floatFromInt(meter_start)), @as(u16, @intFromFloat((meter_slope * @as(f32, @floatFromInt(sv_arr.*[i].time - sv_arr.*[0].time))) + @as(f32, @floatFromInt(meter_start)))) });
            }
        }
    }
    if (n_existing_60ks == n_pts) return; // If we don't need to continue... don't...

    // Allocate for a new sv array
    var new_sv_arr: []sv.TimingPoint = try std.heap.page_allocator.alloc(sv.TimingPoint, n_pts - n_existing_60ks); // Only allocate for the points we need
    defer (std.heap.page_allocator.free(new_sv_arr));
    var idx: usize = 0; // holds index of new_sv_arr
    var curr_meter: f32 = @as(f32, @floatFromInt(meter_start));

    // That should work??
    for (1..sv_arr.*.len) |i| {
        if (sv_arr.*[i].is_inh == 0) { // If greenline
            if (sv_arr.*[i - 1].time != sv_arr.*[i].time) { // If no point exists on it
                curr_meter = (meter_slope * @as(f32, @floatFromInt(sv_arr.*[i].time - sv_arr.*[0].time))) + @as(f32, @floatFromInt(meter_start));
                std.debug.print("curr_meter = {d:.2}\n", .{curr_meter}); // DBG
                new_sv_arr[idx] = sv.TimingPoint{
                    .time = sv_arr.*[i].time,
                    .value = 1.0,
                    .meter = @as(u16, @intFromFloat(curr_meter)),
                    .sample_set = 1,
                    .volume = 100,
                    .is_inh = 1,
                    .effects = 0,
                };
                idx += 1;
            }
        }
    }

    // FOR SOME REASON THE PROGRAM HAS TROUBLE PARSING THE FILE AFTER THESE ARE WRITTEN... FIX THIS

    // Merge these two
    try sv.mergeSvArrs(sv_arr, new_sv_arr);
}
