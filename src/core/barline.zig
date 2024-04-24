const std = @import("std");
const sv = @import("./sv.zig");
const osufile = @import("./osufileio.zig");
const com = @import("../util/common.zig");

pub const BarlineError = error{
    InvalidTimeRange,
};

// TODO: Make this work better w/ other horizontal res
pub inline fn pxDistToSV(px: u16, target_hres: u16) f32 {
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

pub fn oneMsBarlines(start_bpm: f32, start_time: i32, end_time: i32) ![]sv.TimingPoint {
    if ((end_time - start_time) < 1) return BarlineError.InvalidTimeRange;
    const dist_time: usize = @intCast(end_time - start_time);
    var tp: sv.TimingPoint = try std.heap.page_allocator.alloc(sv.TimingPoint, dist_time);
    for (0..tp.len) |i| {
        tp[i] = sv.TimingPoint{
            .time = start_time + @as(i32, @intCast(i)),
            .value = (60000 / start_bpm),
            .meter = 4,
            .volume = 100,
            .is_inh = 1,
            .sample_set = 0,
            .effects = 0,
        };
    }
    return tp;
}
