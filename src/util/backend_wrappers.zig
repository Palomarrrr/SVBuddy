const std = @import("std");

const com = @import("./common.zig");
const undo = @import("./undo.zig");
const sv = @import("../core/sv.zig");
const bl = @import("../core/barline.zig");
const hobj = @import("../core/hitobj.zig");
const osufile = @import("../core/osufileio.zig");
const timing = @import("../core/timing.zig");
const pread = @import("./proc_read.zig");

pub const BackendError = error{
    EffectDeprecated,
    SectionConflict,
    SectionDNE,
    InvalidFormat,
};

// Shitty temp fix just to get this feature working
// TODO - Find a better way of knowing where the volume and kiai fields will be
const VOLUME_FIELD_LOCATION = [_]u8{ 2, 2, 3, 4 };

pub fn applySVFn(opt_targ: ?*osufile.OsuFile, params: anytype) !void {
    if (opt_targ) |target| {
        std.debug.print("options:{b}\n", .{params[15][0]});

        // Refresh the file incase any changes were made
        try target.*.refresh();

        const start: i32 = try timing.timeStrToTick(params[1]);
        const end: i32 = try timing.timeStrToTick(params[2]);
        var arg = [_]f32{0} ** 6;

        arg[0] = try std.fmt.parseFloat(f32, params[3]);
        arg[1] = try std.fmt.parseFloat(f32, params[4]);
        arg[2] = std.fmt.parseFloat(f32, params[5]) catch 0.0;
        arg[3] = std.fmt.parseFloat(f32, params[6]) catch 0.0;
        arg[4] = std.fmt.parseFloat(f32, params[7]) catch 0.0;
        arg[5] = std.fmt.parseFloat(f32, params[8]) catch 0.0;

        const vol_location: usize = VOLUME_FIELD_LOCATION[params[0][1] - '0'];
        const vol: u8 = @intFromFloat(arg[vol_location]);
        const effect: u8 = @intFromFloat(arg[vol_location + 1]);

        const ext_tp = try target.*.extentsOfSection(start, end, sv.TimingPoint);
        const ext_hobj = try target.*.extentsOfSection(start, end, hobj.HitObject);

        const bpm = try target.*.findSectionInitialBPM(ext_tp[0]);
        var tp = try com.create(sv.TimingPoint);
        defer std.heap.page_allocator.free(tp);

        // Create undo entry
        var bck = try com.create(sv.TimingPoint);
        defer std.heap.page_allocator.free(bck);
        _ = try target.loadObjArr(ext_tp[0], ext_tp[2], &bck);
        try createUndo(start, end, bck, false);

        if (params[0][1] != '4' and params[0][1] != '5') { // Janky fix to make sure that we aren't generating sv when adjusting an old section
            var hobjs = try com.create(hobj.HitObject);
            defer std.heap.page_allocator.free(hobjs);
            const keep_prev: bool = !((params[15][0] & 0x4) == 1);

            if (ext_hobj[2] == 0 or (params[15][0] & 0x1) == 0) { // If no hit objs
                try sv.createNewSVSection(&tp, null, start, end, 12, bpm[0], keep_prev, vol, effect); // TODO: ADD SNAPPING
            } else {
                //if (params[15][0] & 0x1 == 1) try target.loadObjArr(ext_hobj[0], ext_hobj[2], &hobjs); // Check if we even want to snap things to the notes
                try target.loadObjArr(ext_hobj[0], ext_hobj[2], &hobjs); // TODO: Make sure this works the same (it should in theory)
                try sv.createNewSVSection(&tp, hobjs, start, end, 12, bpm[0], keep_prev, vol, effect);
            }

            if (ext_tp[2] != 0 and (params[15][0] & 0x4) == 0) { // If points existed previously | this is only important if we have uninherited timing points
                var tp2 = try com.create(sv.TimingPoint);
                _ = try target.loadObjArr(ext_tp[0], ext_tp[2], &tp2);
                defer std.heap.page_allocator.free(tp2);

                const n_inh = sv.getNumInherited(tp2);
                const n_uinh = tp2.len - n_inh;

                if (n_uinh != 0) { // if there are uninherited points in the section
                    var uinh = if (params[15][0] & 0x8 != 0) try std.heap.page_allocator.alloc(sv.TimingPoint, n_uinh * 2) else try std.heap.page_allocator.alloc(sv.TimingPoint, n_uinh); // build an array w/ only uninherited
                    //defer std.heap.page_allocator.free(uinh); // TODO: CHECK IF THIS FUCKS THINGS
                    var i: usize = 0;
                    for (tp2) |p| {
                        if (p.is_inh == 1) {
                            uinh[i] = p;
                            if ((params[15][0] & 0x8) != 0) {
                                uinh[i + 1] = sv.TimingPoint{ // TODO: DONT GENERATE IF NOTE EXISTS ON THIS SINCE THERE WILL ALREADY BE A INH POINT THERE
                                    .time = p.time,
                                    .is_inh = 0,
                                    .value = -1,
                                    .meter = p.meter,
                                    .volume = p.volume,
                                    .effects = p.effects,
                                    .sample_set = p.sample_set,
                                };
                                i += 2;
                            } else {
                                i += 1;
                            }
                        }
                    }
                    try sv.mergeSvArrs(&tp, uinh); // Merge the two sv arrs
                    if (params[15][0] & 0x8 != 0 and params[15][0] & 0x1 == 1) try sv.pruneUnusedSv(&tp, hobjs); // check for param 0x1 just incase | TODO: harden pruneUnusedSv for hobjs.len == 0
                }
            }
        } else {
            if (ext_tp[2] == 0) return BackendError.SectionDNE;
            _ = try target.loadObjArr(ext_tp[0], ext_tp[2], &tp);
        }
        //for (tp) |u| std.debug.print("{s}", .{try u.toStr()}); // DBG

        // Apply the effect
        switch (params[0][1] - '0') {
            0 => try sv.linear(tp, arg[0], arg[1], bpm[0]),
            1 => try sv.exponential(tp, arg[0], arg[1], bpm[0]),
            2 => try sv.sinusoidal(tp, arg[0], arg[1], arg[2], bpm[0]),
            3 => try sv.bezier(tp, arg[0], arg[1], arg[2], arg[3], bpm[0]),
            4 => try sv.scaleSection(tp, arg[0], arg[1], bpm[0]),
            5 => try sv.volumeLinear(tp, @as(u8, @truncate(@as(u32, @intFromFloat(arg[0])))), @as(u8, @truncate(@as(u32, @intFromFloat(arg[1]))))),
            else => unreachable,
        }

        try target.*.placeSection(ext_tp[0], ext_tp[1], tp);
    } else return osufile.OsuFileIOError.FileDNE;
}

pub fn applyHObjFn(opt_targ: ?*osufile.OsuFile, params: anytype) !void {
    if (opt_targ) |target| {
        // Refresh the file incase any changes were made
        try target.*.refresh();

        const start: i32 = try timing.timeStrToTick(params[1]);
        const end: i32 = try timing.timeStrToTick(params[2]);
        const val1: f32 = std.fmt.parseFloat(f32, params[3]) catch 0;
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
        //defer std.heap.page_allocator.free(tps);
        defer std.heap.page_allocator.free(hobjs);

        if (ext_tp[2] != 0) _ = try target.loadObjArr(ext_tp[0], ext_tp[2], &tps);

        _ = try target.loadObjArr(ext_hobj[0], ext_hobj[2], &hobjs);

        try createUndo(start, end, hobjs, false); // TESTING

        const bpm = try target.*.findSectionInitialBPM(ext_tp[0]);

        switch (params[0][1] - '0') {
            0 => try hobj.snapNotesTo(hobjs, params[3], tps, bpm[0], @as(i32, @intFromFloat(bpm[1]))),
            //1 => ,
            2 => try hobj.toUnhittableNote(&hobjs, @as(i32, @intFromFloat(val1))),
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
        const val5: f32 = std.fmt.parseFloat(f32, params[7]) catch 0;
        const val6: f32 = std.fmt.parseFloat(f32, params[8]) catch 0;
        const val7: f32 = std.fmt.parseFloat(f32, params[9]) catch 0;
        const val8: f32 = std.fmt.parseFloat(f32, params[10]) catch 0;
        const val9: f32 = std.fmt.parseFloat(f32, params[11]) catch 0;

        const ext_tp = try target.*.extentsOfSection(start, end, sv.TimingPoint);

        var bck = try com.create(sv.TimingPoint);
        _ = try target.loadObjArr(ext_tp[0], ext_tp[2], &bck);
        try createUndo(start, end, bck, false); // TESTING

        const tps = try com.create(sv.TimingPoint);
        defer std.heap.page_allocator.free(tps);

        //if (ext_tp[2] != 0) return BackendError.SectionConflict; // Either remove this or only make it trigger on a different case

        const bpm = try target.*.findSectionInitialBPM(ext_tp[0]);
        var tp_out: ?[]sv.TimingPoint = null; // Prolly doesnt need to be opt

        switch (params[0][1] - '0') {
            0 => {
                const chance: u8 = @as(u8, @intFromFloat(val3));
                tp_out = try bl.staticRandomBarlines(bpm[0], start, end, chance, val1, val2);
            },
            1 => {
                return BackendError.EffectDeprecated; // Irrelivant after blcreator exists
                //const res: u8 = @as(u8, @intFromFloat(val3));
                //tp_out = try bl.linear60kBarline(bpm[0], start, end, val1, val2, 1920, res);
            },
            2 => {
                // Set up opts
                var opts: u8 = 0;
                opts |= @as(u8, @intFromFloat(val8)); // Escape notes in this section
                opts |= (@as(u8, @intFromFloat(val9)) << 1); // Omit first barline of section end

                tp_out = try bl.create60kSection(bpm[0], start, end, opts);
                if (val3 == 1) { // If line edit is enabled
                    const res: u8 = @as(u8, @intFromFloat(val7));
                    try bl.linear60kBarline(&(tp_out.?), val1, val2, 1920, res); // Why is this optional??
                }
                if (val6 == 1) { // If meter edit is enabled
                    const meter_start: u16 = @as(u16, @intFromFloat(val4));
                    const meter_end: u16 = @as(u16, @intFromFloat(val5));
                    try bl.linear60kMeter(&(tp_out.?), meter_start, meter_end);
                }
            },
            else => unreachable,
        }
        if (tp_out) |tp| {
            try target.*.placeSection(ext_tp[0], ext_tp[1], tp); // Place
        } else unreachable;
    } else return osufile.OsuFileIOError.FileDNE;
}

pub fn initTargetFile(params: anytype) !?*osufile.OsuFile {
    std.debug.print("LOG: Initializing file: `{s}`\n", .{params[1]});
    const retval: *osufile.OsuFile = try std.heap.page_allocator.create(osufile.OsuFile);
    try retval.*.init(params[1]);
    if (params[15][0] & 0x40 != 0) {
        const bckup_path = try retval.*.createBackup();
        defer std.heap.page_allocator.free(bckup_path);
        std.debug.print("LOG: Created backup file at `{s}`!\n", .{bckup_path});
    }
    return retval;
}

inline fn createUndo(start: i32, end: i32, cont: anytype, is_linked: bool) !void {
    const node: *undo.UndoNode = try std.heap.page_allocator.create(undo.UndoNode);
    try node.*.init(start, end, cont);
    if (is_linked) {
        const parent = undo.UNDO_HEAD orelse unreachable; // This fn shouldn't be called without a parent being made before it
        const last_link = parent.getLastLink(); // Get the last link in the chain
        last_link.*.linked = node;
    } else undo.push(node, .undo);
}

// TODO: Test if this works
pub fn undoLast(opt_targ: ?*osufile.OsuFile, direction: undo.Direction) !void {
    const opposite_dir: undo.Direction = switch (direction) {
        .undo => .redo,
        .redo => .undo,
    };
    if (opt_targ) |target| {
        if ((if (direction == .undo) undo.UNDO_HEAD else undo.REDO_HEAD)) |_| { // Nightmare
            var node = try undo.pop(direction);
            const inverse_node = try std.heap.page_allocator.create(undo.UndoNode); // This node is going to the opposite stack
            var cur_inv_node: *undo.UndoNode = inverse_node;
            while (true) {
                switch (node.*.cont_t) {
                    .TimePoint => {
                        const exts = try target.*.extentsOfSection(node.*.extents[0], node.*.extents[1], sv.TimingPoint);

                        var tp: []sv.TimingPoint = try com.create(sv.TimingPoint);
                        //defer std.heap.page_allocator.free(sv.TimingPoint); // Wouldn't this leak?

                        try target.loadObjArr(exts[0], exts[2], &tp);
                        try cur_inv_node.*.init(node.*.extents[0], node.*.extents[1], tp);

                        try target.*.placeSection(exts[0], exts[1], node.*.tp);
                    },
                    .HitObj => {
                        const exts = try target.*.extentsOfSection(node.*.extents[0], node.*.extents[1], hobj.HitObject);

                        // Capture what is currently there
                        var hobjs: []hobj.HitObject = try com.create(hobj.HitObject);
                        //defer std.heap.page_allocator.free(hobj.HitObject);

                        try target.loadObjArr(exts[0], exts[2], &hobjs);
                        try cur_inv_node.*.init(node.*.extents[0], node.*.extents[1], hobjs);

                        try target.*.placeSection(exts[0], exts[1], node.*.hobj);
                    },
                }
                if (node.*.linked) |link| { // If there is a linked node
                    node = link; // Advance the node ptr
                    cur_inv_node.*.linked = try std.heap.page_allocator.create(undo.UndoNode); // And make sure to create a matching redo node
                    cur_inv_node = cur_inv_node.*.linked orelse unreachable; // This was literally just fucking declared... please
                } else break;
            }
            std.debug.print("LOG: Pushing node in the {any} direction!\n", .{opposite_dir});
            undo.push(inverse_node, opposite_dir);
        } else return undo.UndoError.EndOfStack;
    } else return osufile.OsuFileIOError.FileDNE;
}

pub fn preadTest(preader: *pread.ProcReader) ![]u8 {
    return try preader.*.toStr();
}
