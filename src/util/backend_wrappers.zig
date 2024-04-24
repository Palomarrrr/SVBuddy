const std = @import("std");

const com = @import("./common.zig");
const sv = @import("../core/sv.zig");
const bl = @import("../core/barline.zig");
const hobj = @import("../core/hitobj.zig");
const osufile = @import("../core/osufileio.zig");
const timing = @import("../core/timing.zig");

pub const BackendError = error{
    SectionConflict,
};

pub fn applySVFn(opt_targ: ?*osufile.OsuFile, params: anytype) !void {
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

        //std.debug.print("{}:{}:{d:.2}:{d:.2}:{}\n", .{ start, end, val1, val2, val3 });

        const ext_tp = try target.*.extentsOfSection(start, end, sv.TimingPoint);
        const ext_hobj = try target.*.extentsOfSection(start, end, hobj.HitObject);
        std.debug.print("Found section extents\n", .{});

        const bpm = try target.*.findSectionInitialBPM(ext_tp[0]);
        std.debug.print("Found section bpm\n", .{});
        //std.debug.print("bpm={d:.2}\n", .{bpm});
        var tp = try com.create(sv.TimingPoint);
        var hobjs = try com.create(hobj.HitObject);
        defer std.heap.page_allocator.free(hobjs);
        //defer std.heap.page_allocator.free(tp); // TESTTHIS

        std.debug.print("Creating objarrs\n", .{});
        if (ext_hobj[2] == 0 or (params[9][0] & 0x1) == 0) { // If no hit objs
            std.debug.print("Making new tpobjarr1\n", .{});
            std.debug.print("bpmext:{any}\n", .{ext_hobj});
            try sv.createNewSVSection(&tp, null, start, end, 12, bpm[0]); // TODO: ADD SNAPPING
        } else {
            try target.loadObjArr(ext_hobj[0], ext_hobj[2], &hobjs);
            std.debug.print("made tpobjarr1\n", .{});
            try sv.createNewSVSection(&tp, hobjs, start, end, 12, bpm[0]);
        }

        if (ext_tp[2] != 0 and (params[9][0] & 0x4) == 0) { // If points existed previously | this is only important if we have uninherited timing points
            var tp2 = try com.create(sv.TimingPoint);
            _ = try target.loadObjArr(ext_tp[0], ext_tp[2], &tp2);
            std.debug.print("made tpobjarr2\n", .{});
            defer std.heap.page_allocator.free(tp2);

            const n_uinh = tp2.len - sv.getNumInherited(tp2);

            if (n_uinh != 0) { // if there are uninherited points in the section
                var uinh = if (params[9][0] & 0x8 != 0) try std.heap.page_allocator.alloc(sv.TimingPoint, n_uinh * 2) else try std.heap.page_allocator.alloc(sv.TimingPoint, n_uinh); // build an array w/ only uninherited
                var i: usize = 0;
                for (tp2) |p| {
                    if (p.is_inh == 1) {
                        uinh[i] = p;
                        if ((params[9][0] & 0x8) != 0) {
                            uinh[i + 1] = sv.TimingPoint{ // TODO: DONT GENERATE IF NOTE EXISTS ON THIS SINCE THERE WILL ALREADY BE A INH POINT THERE
                                .time = p.time,
                                .is_inh = 0,
                                .value = -1,
                                .meter = p.meter,
                                .volume = p.volume,
                                .effects = p.effects,
                                .sample_set = p.sample_set,
                            };
                        }
                        i += 2;
                    }
                }
                try sv.mergeSvArrs(&tp, uinh); // Merge the two sv arrs
                if (params[9][0] & 0x8 != 0 and params[9][0] & 0x1 == 1) try sv.pruneUnusedSv(&tp, hobjs); // check for param 0x1 just incase | TODO: harden pruneUnusedSv for hobjs.len == 0
                for (tp) |u| std.debug.print("{s}", .{try u.toStr()});
            }
        }

        // Apply the effect
        switch (params[0][1] - '0') {
            0 => try sv.linear(tp, val1, val2, bpm[0]),
            1 => try sv.exponential(tp, val1, val2, bpm[0]),
            2 => try sv.sinusoidal(tp, val1, val2, val3, bpm[0]),
            4 => try sv.scaleSection(tp, val1, val2, bpm[0]),
            else => unreachable,
        }

        try target.*.placeSection(ext_tp[0], ext_tp[1], tp); // Place
    } else return osufile.OsuFileIOError.FileDNE;
}

pub fn applyHObjFn(opt_targ: ?*osufile.OsuFile, params: anytype) !void {
    if (opt_targ) |target| {
        // Refresh the file incase any changes were made
        try target.*.refresh();

        const start: i32 = try timing.timeStrToTick(params[1]);
        const end: i32 = try timing.timeStrToTick(params[2]);
        const val1: f32 = std.fmt.parseFloat(f32, params[3]) catch 0;
        _ = val1;
        const val2: f32 = std.fmt.parseFloat(f32, params[4]) catch 0;
        _ = val2;
        const val3: f32 = std.fmt.parseFloat(f32, params[5]) catch 0;
        _ = val3;
        const val4: f32 = std.fmt.parseFloat(f32, params[6]) catch 0;
        _ = val4;

        const ext_tp = try target.*.extentsOfSection(start, end, sv.TimingPoint);
        const ext_hobj = try target.*.extentsOfSection(start, end, hobj.HitObject);

        var tps = try com.create(sv.TimingPoint);
        var hobjs = try com.create(hobj.HitObject);
        defer std.heap.page_allocator.free(tps);
        defer std.heap.page_allocator.free(hobjs);

        if (ext_tp[2] != 0) _ = try target.loadObjArr(ext_tp[0], ext_tp[2], &tps);
        _ = try target.loadObjArr(ext_hobj[0], ext_hobj[2], &hobjs);

        const bpm = try target.*.findSectionInitialBPM(ext_tp[0]);

        switch (params[0][1] - '0') {
            0 => try hobj.snapNotesTo(hobjs, params[3], tps, bpm[0], @as(i32, @intFromFloat(bpm[1]))),
            //1 => ,
            //2 => ,
            else => unreachable,
        }
        try target.*.placeSection(ext_hobj[0], ext_hobj[1], hobjs); // Place
    } else return osufile.OsuFileIOError.FileDNE;
}

pub fn applyBarlineFn(opt_targ: ?*osufile.OsuFile, params: anytype) !void {
    if (opt_targ) |target| {
        // Refresh the file incase any changes were made
        try target.*.refresh();

        const start: i32 = try timing.timeStrToTick(params[1]);
        const end: i32 = try timing.timeStrToTick(params[2]);
        const val1: f32 = std.fmt.parseFloat(f32, params[3]) catch 0;
        const val2: f32 = std.fmt.parseFloat(f32, params[4]) catch 0;
        const val3: f32 = std.fmt.parseFloat(f32, params[5]) catch 0;
        const val4: f32 = std.fmt.parseFloat(f32, params[6]) catch 0;
        _ = val4;

        const ext_tp = try target.*.extentsOfSection(start, end, sv.TimingPoint);

        const tps = try com.create(sv.TimingPoint);
        defer std.heap.page_allocator.free(tps);

        if (ext_tp[2] != 0) return BackendError.SectionConflict;

        std.debug.print("exts: {}=>{}\n", .{ ext_tp[0], ext_tp[1] });
        const bpm = try target.*.findSectionInitialBPM(ext_tp[0]);
        std.debug.print("bpm: {d:.2}\n", .{bpm[0]});
        var tp_out: ?[]sv.TimingPoint = null; // Prolly doesnt need to be opt

        switch (params[0][1] - '0') {
            0 => {
                const chance: u8 = @as(u8, @intFromFloat(val3));
                std.debug.print("chance: {}\n", .{chance});
                tp_out = try bl.staticRandomBarlines(bpm[0], start, end, chance, val1, val2);
                for (tp_out.?) |t| {
                    std.debug.print("{s}\n", .{try t.toStr()});
                }
            },
            //1 => ,
            //2 => ,
            else => unreachable,
        }
        if (tp_out) |tp| {
            try target.*.placeSection(ext_tp[0], ext_tp[1], tp); // Place
        } else unreachable;
    } else return osufile.OsuFileIOError.FileDNE;
}

pub fn initTargetFile(params: anytype) !?*osufile.OsuFile {
    const retval: *osufile.OsuFile = try std.heap.page_allocator.create(osufile.OsuFile);
    try retval.*.init(params[1]);
    if (params[9][0] & 0x40 != 0) {
        const bckup_path = try retval.*.createBackup();
        defer std.heap.page_allocator.free(bckup_path);
        std.debug.print("LOG: Created backup file at `{s}`!\n", .{bckup_path});
    }
    return retval;
}
