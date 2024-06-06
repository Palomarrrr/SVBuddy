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
    SectionConflict,
    SectionDNE,
};

pub fn applySVFn(opt_targ: ?*osufile.OsuFile, params: anytype) !void {
    if (opt_targ) |target| {
        std.debug.print("options:{b}\n", .{params[9][0]});

        // Refresh the file incase any changes were made
        try target.*.refresh();

        const start: i32 = try timing.timeStrToTick(params[1]);
        const end: i32 = try timing.timeStrToTick(params[2]);
        const val1: f32 = try std.fmt.parseFloat(f32, params[3]);
        const val2: f32 = try std.fmt.parseFloat(f32, params[4]);
        const val3: f32 = std.fmt.parseFloat(f32, params[5]) catch 0;
        const val4: f32 = std.fmt.parseFloat(f32, params[6]) catch 0;
        _ = val4;

        //std.debug.print("RECIEVED FROM MAIN: {}:{}:{d:.2}:{d:.2}:{}\n", .{ start, end, val1, val2, val3 });

        const ext_tp = try target.*.extentsOfSection(start, end, sv.TimingPoint);
        std.debug.print("\n\n", .{});
        const ext_hobj = try target.*.extentsOfSection(start, end, hobj.HitObject);
        //std.debug.print("Found section extents: {any} | {any}\n", .{ ext_tp, ext_hobj });

        const bpm = try target.*.findSectionInitialBPM(ext_tp[0]);
        std.debug.print("Found section bpm\n", .{});
        var tp = try com.create(sv.TimingPoint);
        defer std.heap.page_allocator.free(tp);

        // TESTING
        var bck = try com.create(sv.TimingPoint);
        defer std.heap.page_allocator.free(bck);
        _ = try target.loadObjArr(ext_tp[0], ext_tp[2], &bck);
        std.debug.print("Made BCK for backup\n", .{});
        std.debug.print("BCK:{any},{}\n", .{ ext_tp, bck.len });
        try createUndo(start, end, bck, false);
        // TESTING

        //if (params[0][1] != '4' and ext_tp[2] != 0) { // Janky fix to make sure that we aren't generating sv when adjusting an old section
        if (params[0][1] != '4' and params[0][1] != '5') { // Janky fix to make sure that we aren't generating sv when adjusting an old section
            var hobjs = try com.create(hobj.HitObject);
            defer std.heap.page_allocator.free(hobjs);
            const keep_prev: bool = !((params[9][0] & 0x4) == 1);

            std.debug.print("Creating objarrs\n", .{});
            std.debug.print("a\n", .{});
            if (ext_hobj[2] == 0 or (params[9][0] & 0x1) == 0) { // If no hit objs
                std.debug.print("Making new tpobjarr1: HOBJ = 0\n", .{});
                try sv.createNewSVSection(&tp, null, start, end, 12, bpm[0], keep_prev); // TODO: ADD SNAPPING
            } else {
                std.debug.print("b | {any}\n", .{ext_hobj});
                //if (params[9][0] & 0x1 == 1) try target.loadObjArr(ext_hobj[0], ext_hobj[2], &hobjs); // Check if we even want to snap things to the notes
                try target.loadObjArr(ext_hobj[0], ext_hobj[2], &hobjs); // TODO: Make sure this works the same (it should in theory)
                std.debug.print("Making new tpobjarr1\n", .{});
                try sv.createNewSVSection(&tp, hobjs, start, end, 12, bpm[0], keep_prev);
            }

            std.debug.print("made tpobjarr1\n", .{});

            if (ext_tp[2] != 0 and (params[9][0] & 0x4) == 0) { // If points existed previously | this is only important if we have uninherited timing points
                var tp2 = try com.create(sv.TimingPoint);
                _ = try target.loadObjArr(ext_tp[0], ext_tp[2], &tp2);
                std.debug.print("made tpobjarr2\n", .{});
                defer std.heap.page_allocator.free(tp2);

                const n_inh = sv.getNumInherited(tp2);
                const n_uinh = tp2.len - n_inh;

                if (n_uinh != 0) { // if there are uninherited points in the section
                    var uinh = if (params[9][0] & 0x8 != 0) try std.heap.page_allocator.alloc(sv.TimingPoint, n_uinh * 2) else try std.heap.page_allocator.alloc(sv.TimingPoint, n_uinh); // build an array w/ only uninherited
                    //defer std.heap.page_allocator.free(uinh); // TODO: CHECK IF THIS FUCKS THINGS
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
                                i += 2;
                            } else {
                                i += 1;
                            }
                        }
                    }
                    try sv.mergeSvArrs(&tp, uinh); // Merge the two sv arrs
                    if (params[9][0] & 0x8 != 0 and params[9][0] & 0x1 == 1) try sv.pruneUnusedSv(&tp, hobjs); // check for param 0x1 just incase | TODO: harden pruneUnusedSv for hobjs.len == 0
                }
            }
        } else {
            if (ext_tp[2] == 0) return BackendError.SectionDNE;
            _ = try target.loadObjArr(ext_tp[0], ext_tp[2], &tp);
            //try createUndo(ext_tp, tp, false); // TESTING
        }
        for (tp) |u| std.debug.print("{s}", .{try u.toStr()});

        // Apply the effect
        switch (params[0][1] - '0') {
            0 => try sv.linear(tp, val1, val2, bpm[0]),
            1 => try sv.exponential(tp, val1, val2, bpm[0]),
            2 => try sv.sinusoidal(tp, val1, val2, val3, bpm[0]),
            4 => try sv.scaleSection(tp, val1, val2, bpm[0]),
            5 => try sv.volumeLinear(tp, @as(u8, @truncate(@as(u32, @intFromFloat(val1)))), @as(u8, @truncate(@as(u32, @intFromFloat(val2))))),
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
        const val2: f32 = std.fmt.parseFloat(f32, params[4]) catch 0;
        _ = val2;
        const val3: f32 = std.fmt.parseFloat(f32, params[5]) catch 0;
        _ = val3;
        const val4: f32 = std.fmt.parseFloat(f32, params[6]) catch 0;
        _ = val4;

        const ext_tp = try target.*.extentsOfSection(start, end, sv.TimingPoint);
        std.debug.print("TimingPoint Extents: {any}\n", .{ext_tp});
        const ext_hobj = try target.*.extentsOfSection(start, end, hobj.HitObject);
        std.debug.print("HitObject Extents: {any}\n", .{ext_hobj});

        var tps = try com.create(sv.TimingPoint);
        var hobjs = try com.create(hobj.HitObject);
        //defer std.heap.page_allocator.free(tps);
        defer std.heap.page_allocator.free(hobjs);

        if (ext_tp[2] != 0) _ = try target.loadObjArr(ext_tp[0], ext_tp[2], &tps);
        std.debug.print("Finished loading ext_tp\n", .{});

        _ = try target.loadObjArr(ext_hobj[0], ext_hobj[2], &hobjs);
        std.debug.print("Finished loading ext_hobj: {},{}\n", .{ ext_hobj[2], hobjs.len });

        try createUndo(start, end, hobjs, false); // TESTING

        const bpm = try target.*.findSectionInitialBPM(ext_tp[0]);
        std.debug.print("Found bpm\n", .{});

        switch (params[0][1] - '0') {
            0 => try hobj.snapNotesTo(hobjs, params[3], tps, bpm[0], @as(i32, @intFromFloat(bpm[1]))),
            //1 => ,
            2 => try hobj.toUnhittableNote(&hobjs, @as(i32, @intFromFloat(val1))),
            else => unreachable,
        }
        std.debug.print("FN Called\n", .{});
        for (hobjs) |h| std.debug.print("{any}\n", .{h});
        try target.*.placeSection(ext_hobj[0], ext_hobj[1], hobjs); // Place
        std.debug.print("Placed Section\n", .{});
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

        const bck = try com.create(sv.TimingPoint);
        _ = try target.loadObjArr(ext_tp[0], ext_tp[2], &bck);
        try createUndo(start, end, bck, false); // TESTING

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
    std.debug.print("inittfile\n{s}\n", .{params[1]});
    const retval: *osufile.OsuFile = try std.heap.page_allocator.create(osufile.OsuFile);
    try retval.*.init(params[1]);
    if (params[9][0] & 0x40 != 0) {
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
            std.debug.print("Pushing node in the {any} direction!\n", .{opposite_dir});
            undo.push(inverse_node, opposite_dir);
        } else return undo.UndoError.EndOfStack;
    } else return osufile.OsuFileIOError.FileDNE;
}

pub fn preadTest(preader: *pread.UnixProcReader) ![]u8 {
    return try preader.*.toStr();
}
