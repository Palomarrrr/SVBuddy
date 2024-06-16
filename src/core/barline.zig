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

pub fn static60kBarline(start_bpm: f32, start_time: i32, end_time: i32, bl_dist: f32, target_hres: f32) ![]sv.TimingPoint {
    var tp = try std.heap.page_allocator.alloc(sv.TimingPoint, 3); // We only need 3 points, the 60k line, the sv applied to it, and the ending point
    tp[0] = sv.TimingPoint{ // Make an initial point
        .time = start_time,
        .value = 1,
        .meter = 4,
        .volume = 100,
        .is_inh = 1,
        .sample_set = 0,
        .effects = 0,
    };
    tp[1] = sv.TimingPoint{ // Make an initial point
        .time = start_time,
        .value = pxDistToSV(bl_dist, target_hres),
        .meter = 4,
        .volume = 100,
        .is_inh = 1,
        .sample_set = 0,
        .effects = 0,
    };
    tp[2] = sv.TimingPoint{ // Make an initial point
        .time = end_time,
        .value = (60000 / start_bpm),
        .meter = 4,
        .volume = 100,
        .is_inh = 1,
        .sample_set = 0,
        .effects = 0,
    };
    // yeah... thats about it
    return tp;
}

// IDEA:
// Make an entire barline effect editor with lines on screen (sv) transitions
// and barline frequency (meter) transitions as well as some other stuff

// TODO: These should initially check if they are already in a 60k section
pub fn linear60kBarline(start_bpm: f32, start_time: i32, end_time: i32, bl_start: f32, bl_end: f32, target_hres: f32, effect_snapping: u8) ![]sv.TimingPoint {
    var curr_bl: f32 = bl_start;
    var curr_time: i32 = start_time;
    const inc: i32 = @as(i32, @intFromFloat(60000.0 / start_bpm / @as(f32, @floatFromInt(effect_snapping))));
    const n_pts: u32 = @intCast(@divTrunc((end_time - start_time), inc));
    const bl_slope = ((bl_end - bl_start) / @as(f32, @floatFromInt(n_pts)));
    const tp = try std.heap.page_allocator.alloc(sv.TimingPoint, n_pts + 2);
    tp[0] = sv.TimingPoint{ // Make an initial point
        .time = start_time,
        .value = 1,
        .meter = 1,
        .volume = 100,
        .is_inh = 1,
        .sample_set = 0,
        .effects = 0,
    };

    // Linear progression
    for (1..tp.len) |i| {
        tp[i] = sv.TimingPoint{ // Make an initial point
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

    tp[n_pts + 1] = sv.TimingPoint{
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

//pub fn linear60kMeter(start_bpm: f32, start_time: i32, end_time: i32, meter_start: u8, meter_end: u8) ![]sv.TimingPoint {
//}

//pub fn exponential60kBarline( start_bpm: f32, start_time: i32, end_time: i32, bl_start: f32, bl_end: f32, target_hres: f32, effect_snapping: i32) ![]sv.TimingPoint {
//   const n_pts: u32 = @intCast(@divTrunc((end_time - start_time), @as(i32, @intFromFloat(60000.0 / start_bpm / @as(f32, @floatFromInt(effect_snapping))))));
//   const tp = try std.heap.page_allocator.alloc(sv.TimingPoint, n_pts);
//
//   // Exponential progression
//   for(0..tp.len) |i| {
//
//   }
//
//   return tp;
//}
