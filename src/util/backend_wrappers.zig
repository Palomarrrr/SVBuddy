const std = @import("std");

const com = @import("./common.zig");
const sv = @import("../core/libsv.zig");
const hobj = @import("../core/hitobj.zig");
const osufile = @import("../core/osufileio.zig");
const timing = @import("../core/libtiming.zig");

pub fn applyFn(opt_targ: ?*osufile.OsuFile, params: anytype) !void {
    if (opt_targ) |target| {

        // Refresh the file incase any changes were made
        try target.*.refresh();

        const start: i32 = try timing.timeStrToTick(params[1]);
        const end: i32 = try timing.timeStrToTick(params[2]);
        const val1: f32 = try std.fmt.parseFloat(f32, params[3]);
        const val2: f32 = try std.fmt.parseFloat(f32, params[4]);
        const val3: f32 = std.fmt.parseFloat(f32, params[5]) catch 0; // FIXME: THIS FAILS -- I think this is fixed?
        const val4: f32 = std.fmt.parseFloat(f32, params[6]) catch 0;
        _ = val4;

        std.debug.print("{}:{}:{d:.2}:{d:.2}:{}\n", .{ start, end, val1, val2, val3 });

        const ext_tp = try target.*.extentsOfSection(start, end, sv.TimingPoint);
        const ext_hobj = try target.*.extentsOfSection(start, end, hobj.HitObject);

        const bpm: f32 = try target.*.findSectionInitialBPM(ext_tp[0]);
        std.debug.print("bpm={d:.2}\n", .{bpm});
        var tp = try com.create(sv.TimingPoint);

        if (ext_hobj[2] == 0 or (params[9][0] & 0x1) == 0) { // If no hit objs
            try sv.createNewSVSection(&tp, null, start, end, 12, bpm); // TODO: ADD SNAPPING
        } else {
            var hobjs = try com.create(hobj.HitObject);
            defer std.heap.page_allocator.free(hobjs);
            //_ = try osufile.load().hitObjArray(target.*.file.?, ext_hobj[0], ext_hobj[2], &hobjs); // Fetch so that we can create a section off of them
            try target.loadObjArr(ext_hobj[0], ext_hobj[2], &hobjs);
            try sv.createNewSVSection(&tp, hobjs, start, end, 12, bpm);
        }

        if (ext_tp[2] != 0 and (params[9][0] & 0x4) == 0) { // If points existed previously | this is only important if we have uninherited timing points
            var tp2 = try com.create(sv.TimingPoint);
            //_ = try osufile.load().timingPointArray(target.*.file.?, ext_tp[0], ext_tp[2], &tp2);
            _ = try target.loadObjArr(ext_tp[0], ext_tp[2], &tp2);
            defer std.heap.page_allocator.free(tp2);

            const n_uinh = tp2.len - sv.getNumInherited(tp2);

            if (n_uinh != 0) { // if there are uninherited points in the section
                var uinh = try std.heap.page_allocator.alloc(sv.TimingPoint, n_uinh * 2); // build an array w/ only uninherited
                var i: usize = 0;
                for (tp2) |p| {
                    if (p.is_inh == 1) {
                        uinh[i] = p;
                        uinh[i + 1] = sv.TimingPoint{ // TODO: DONT GENERATE IF NOTE EXISTS ON THIS SINCE THERE WILL ALREADY BE A INH POINT THERE
                            .time = p.time,
                            .is_inh = 0,
                            .value = -1,
                            .meter = p.meter,
                            .volume = p.volume,
                            .effects = p.effects,
                            .sampleSet = p.sampleSet,
                        };
                        i += 2;
                    }
                }
                for (uinh) |u| std.debug.print("{s}", .{try u.toStr()});
                try sv.mergeSvArrs(&tp, uinh); // Merge the two sv arrs
                for (tp) |u| std.debug.print("{s}", .{try u.toStr()});
            }
        }

        // Apply the effect
        switch (params[0][0] - '0') {
            1 => try sv.linear(tp, val1, val2, bpm),
            2 => try sv.exponential(tp, val1, val2, bpm),
            3 => try sv.sinusoidal(tp, val1, val2, val3, bpm),
            5 => try sv.scaleSection(tp, val1, val2, bpm),
            else => unreachable,
        }

        try target.*.placeSection(ext_tp[0], ext_tp[1], tp); // Place
    } else return osufile.OsuFileIOError.FileDNE;
}

pub fn initTargetFile(params: anytype) !?*osufile.OsuFile {
    const retval: *osufile.OsuFile = try std.heap.page_allocator.create(osufile.OsuFile);
    try retval.*.init(params[1]);
    if (params[9][0] & 8 != 0) {
        const bckup_path = try retval.*.createBackup();
        defer std.heap.page_allocator.free(bckup_path);
        std.debug.print("LOG: Created backup file at `{s}`!\n", .{bckup_path});
    }
    return retval;
}
