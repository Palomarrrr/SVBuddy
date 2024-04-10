const std = @import("std");

const com = @import("./common.zig");
const sv = @import("../core/libsv.zig");
const hobj = @import("../core/hitobj.zig");
const osufile = @import("../core/osufileio.zig");
const timing = @import("../core/libtiming.zig");

pub fn linear(opt_targ: ?*osufile.OsuFile, params: anytype) !void {
    if (opt_targ) |target| {

        // Refresh the file incase any changes were made
        target.*.file.?.close();
        target.*.file.? = try std.fs.openFileAbsolute(target.*.path, .{ .mode = .read_write });

        const start: i32 = try timing.timeStrToTick(params[0]);
        const end: i32 = try timing.timeStrToTick(params[1]);
        const sv_start: f32 = try std.fmt.parseFloat(f32, params[2]);
        const sv_end: f32 = try std.fmt.parseFloat(f32, params[3]);

        const ext_tp = try target.*.extentsOfSection(start, end, sv.TimingPoint);
        const ext_hobj = try target.*.extentsOfSection(start, end, hobj.HitObject);

        const bpm: f32 = try target.*.findSectionInitialBPM(ext_tp[0]);
        var tp = try com.create(sv.TimingPoint);

        if (ext_hobj[2] == 0) { // If no hit objs
            try sv.createNewSVSection(&tp, null, start, end, 12, bpm); // TODO: ADD SNAPPING
        } else {
            var hobjs = try com.create(hobj.HitObject);
            defer std.heap.raw_c_allocator.free(hobjs);
            _ = try osufile.load().hitObjArray(target.*.file.?, ext_hobj[0], ext_hobj[2], &hobjs); // Fetch so that we can create a section off of them
            try sv.createNewSVSection(&tp, hobjs, start, end, 12, bpm);
        }

        if (ext_tp[2] != 0) { // If points existed previously | this is only important if we have uninherited timing points
            var tp2 = try com.create(sv.TimingPoint);
            _ = try osufile.load().timingPointArray(target.*.file.?, ext_tp[0], ext_tp[2], &tp2);
            defer std.heap.raw_c_allocator.free(tp2);

            const n_uinh = tp2.len - sv.getNumInherited(tp2);

            if (n_uinh != 0) { // if there are uninherited points in the section
                var uinh = try std.heap.raw_c_allocator.alloc(sv.TimingPoint, n_uinh); // build an array w/ only uninherited
                var i: usize = 0;
                for (tp2) |p| {
                    if (p.is_inh == 1) {
                        uinh[i] = p;
                        i += 1;
                    }
                }
                try sv.mergeSvArrs(&tp, uinh); // Merge the two sv arrs
            }
        }

        try sv.linear(tp, sv_start, sv_end, bpm); // Apply the effect

        try target.*.placeSection(ext_tp[0], ext_tp[1], tp, .replace); // Place
    } else return osufile.OsuFileIOError.FileDNE;
}

pub fn exponential(opt_targ: ?*osufile.OsuFile, params: anytype) !void {
    if (opt_targ) |target| {

        // Refresh the file incase any changes were made
        target.*.file.?.close();
        target.*.file.? = try std.fs.openFileAbsolute(target.*.path, .{ .mode = .read_write });

        const start: i32 = try timing.timeStrToTick(params[0]);
        const end: i32 = try timing.timeStrToTick(params[1]);
        const sv_start: f32 = try std.fmt.parseFloat(f32, params[2]);
        const sv_end: f32 = try std.fmt.parseFloat(f32, params[3]);

        const ext_tp = try target.*.extentsOfSection(start, end, sv.TimingPoint);
        const ext_hobj = try target.*.extentsOfSection(start, end, hobj.HitObject);

        const bpm: f32 = try target.*.findSectionInitialBPM(ext_tp[0]);
        var tp = try com.create(sv.TimingPoint);

        if (ext_hobj[2] == 0) { // If no hit objs
            try sv.createNewSVSection(&tp, null, start, end, 12, bpm); // TODO: ADD SNAPPING
        } else {
            var hobjs = try com.create(hobj.HitObject);
            defer std.heap.raw_c_allocator.free(hobjs);
            _ = try osufile.load().hitObjArray(target.*.file.?, ext_hobj[0], ext_hobj[2], &hobjs); // Fetch so that we can create a section off of them
            try sv.createNewSVSection(&tp, hobjs, start, end, 12, bpm);
        }

        if (ext_tp[2] != 0) { // If points existed previously | this is only important if we have uninherited timing points
            var tp2 = try com.create(sv.TimingPoint);
            _ = try osufile.load().timingPointArray(target.*.file.?, ext_tp[0], ext_tp[2], &tp2);
            defer std.heap.raw_c_allocator.free(tp2);

            const n_uinh = tp2.len - sv.getNumInherited(tp2);

            if (n_uinh != 0) { // if there are uninherited points in the section
                var uinh = try std.heap.raw_c_allocator.alloc(sv.TimingPoint, n_uinh); // build an array w/ only uninherited
                var i: usize = 0;
                for (tp2) |p| {
                    if (p.is_inh == 1) {
                        uinh[i] = p;
                        i += 1;
                    }
                }
                try sv.mergeSvArrs(&tp, uinh); // Merge the two sv arrs
            }
        }

        try sv.exponential(tp, sv_start, sv_end, bpm); // Apply the effect

        try target.*.placeSection(ext_tp[0], ext_tp[1], tp, .replace); // Place
    } else return osufile.OsuFileIOError.FileDNE;
}

pub fn sinusoidal(opt_targ: ?*osufile.OsuFile, params: anytype) !void {
    if (opt_targ) |target| {

        // Refresh the file incase any changes were made
        target.*.file.?.close();
        target.*.file.? = try std.fs.openFileAbsolute(target.*.path, .{ .mode = .read_write });

        const start: i32 = try timing.timeStrToTick(params[0]);
        const end: i32 = try timing.timeStrToTick(params[1]);
        const sv_trough: f32 = try std.fmt.parseFloat(f32, params[2]);
        const sv_peak: f32 = try std.fmt.parseFloat(f32, params[3]);
        const n_cycles: f32 = try std.fmt.parseFloat(f32, params[4]);

        const ext_tp = try target.*.extentsOfSection(start, end, sv.TimingPoint);
        const ext_hobj = try target.*.extentsOfSection(start, end, hobj.HitObject);

        const bpm: f32 = try target.*.findSectionInitialBPM(ext_tp[0]);
        var tp = try com.create(sv.TimingPoint);

        if (ext_hobj[2] == 0) { // If no hit objs
            try sv.createNewSVSection(&tp, null, start, end, 12, bpm); // TODO: ADD SNAPPING
        } else {
            var hobjs = try com.create(hobj.HitObject);
            defer std.heap.raw_c_allocator.free(hobjs);
            _ = try osufile.load().hitObjArray(target.*.file.?, ext_hobj[0], ext_hobj[2], &hobjs); // Fetch so that we can create a section off of them
            try sv.createNewSVSection(&tp, hobjs, start, end, 12, bpm);
        }

        if (ext_tp[2] != 0) { // If points existed previously | this is only important if we have uninherited timing points
            var tp2 = try com.create(sv.TimingPoint);
            _ = try osufile.load().timingPointArray(target.*.file.?, ext_tp[0], ext_tp[2], &tp2);
            defer std.heap.raw_c_allocator.free(tp2);

            const n_uinh = tp2.len - sv.getNumInherited(tp2);

            if (n_uinh != 0) { // if there are uninherited points in the section
                var uinh = try std.heap.raw_c_allocator.alloc(sv.TimingPoint, n_uinh); // build an array w/ only uninherited
                var i: usize = 0;
                for (tp2) |p| {
                    if (p.is_inh == 1) {
                        uinh[i] = p;
                        i += 1;
                    }
                }
                try sv.mergeSvArrs(&tp, uinh); // Merge the two sv arrs
            }
        }

        try sv.sinusoidal(tp, sv_trough, sv_peak, n_cycles, bpm); // Apply the effect

        try target.*.placeSection(ext_tp[0], ext_tp[1], tp, .replace); // Place
    } else return osufile.OsuFileIOError.FileDNE;
}

pub fn adjust(opt_targ: ?*osufile.OsuFile, params: anytype) !void {
    if (opt_targ) |target| {

        // Refresh the file incase any changes were made
        target.*.file.?.close();
        target.*.file.? = try std.fs.openFileAbsolute(target.*.path, .{ .mode = .read_write });

        const start: i32 = try timing.timeStrToTick(params[0]);
        const end: i32 = try timing.timeStrToTick(params[1]);
        const l_bound: f32 = try std.fmt.parseFloat(f32, params[2]);
        const u_bound: f32 = try std.fmt.parseFloat(f32, params[3]);

        const ext_tp = try target.*.extentsOfSection(start, end, sv.TimingPoint);
        const ext_hobj = try target.*.extentsOfSection(start, end, hobj.HitObject);

        const bpm: f32 = try target.*.findSectionInitialBPM(ext_tp[0]);
        var tp = try com.create(sv.TimingPoint);

        if (ext_hobj[2] == 0) { // If no hit objs
            try sv.createNewSVSection(&tp, null, start, end, 12, bpm); // TODO: ADD SNAPPING
        } else {
            var hobjs = try com.create(hobj.HitObject);
            defer std.heap.raw_c_allocator.free(hobjs);
            _ = try osufile.load().hitObjArray(target.*.file.?, ext_hobj[0], ext_hobj[2], &hobjs); // Fetch so that we can create a section off of them
            try sv.createNewSVSection(&tp, hobjs, start, end, 12, bpm);
        }

        if (ext_tp[2] != 0) { // If points existed previously | this is only important if we have uninherited timing points
            var tp2 = try com.create(sv.TimingPoint);
            _ = try osufile.load().timingPointArray(target.*.file.?, ext_tp[0], ext_tp[2], &tp2);
            defer std.heap.raw_c_allocator.free(tp2);

            const n_uinh = tp2.len - sv.getNumInherited(tp2);

            if (n_uinh != 0) { // if there are uninherited points in the section
                var uinh = try std.heap.raw_c_allocator.alloc(sv.TimingPoint, n_uinh); // build an array w/ only uninherited
                var i: usize = 0;
                for (tp2) |p| {
                    if (p.is_inh == 1) {
                        uinh[i] = p;
                        i += 1;
                    }
                }
                try sv.mergeSvArrs(&tp, uinh); // Merge the two sv arrs
            }
        }

        try sv.scaleSection(tp, l_bound, u_bound, bpm); // Apply the effect

        try target.*.placeSection(ext_tp[0], ext_tp[1], tp, .replace); // Place
    } else return osufile.OsuFileIOError.FileDNE;
}

pub fn initTargetFile(params: anytype) !?*osufile.OsuFile {
    const retval: *osufile.OsuFile = try std.heap.raw_c_allocator.create(osufile.OsuFile);
    try retval.*.init(params[0]);
    if (params[6][0] & 8 != 0) {
        const bckup_path = try retval.*.createBackup();
        defer std.heap.raw_c_allocator.free(bckup_path);
        std.debug.print("LOG: Created backup file at `{s}`!\n", .{bckup_path});
    }
    return retval;
}
