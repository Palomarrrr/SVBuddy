// "My hope is that this code is so awful I'm never allowed to write UI code again."
const std = @import("std");
const capy = @import("capy");
const osufile = @import("./core/osufileio.zig");
const com = @import("./util/common.zig");
const wrapper = @import("./util/backend_wrappers.zig");
const builtin = @import("builtin");

//TMP
const sv = @import("./core/sv.zig");
const hobj = @import("./core/hitobj.zig");
const pread = @import("./util/proc_read.zig");

//=============================================
// TODO
//=============================================
//  * IMPLEMENT VOLUME CHANGES
//  * FIX THE PROBLEM WITH VALUES 3,4,6,8 DEFAULTING TO 170 - Should be fixed
//  * ADD KIAI CHECKBOX / AUTO KIAI ON AND OFF | SAME COULD GO FOR VOLUME
//  * IMPLEMENT SONG PICKER W/ SOME KIND OF FUZZY SEARCH
//=============================================
//  VERY BIG TODO
//=============================================
//  * MAKE THIS PROGRAM STORE CHANGES IN A DIFF FORMAT INSTEAD OF THE DUMB FORMAT ITS IN NOW
//  * SWITCH ALL page_allocator TO GeneralPurposeAllocator or FixedBufferAllocator
//=============================================
// LAYOUT IDEA
//=============================================
//  * Go look at other tools for inspiration on layouts
//=============================================

// This is required for your app to build to WebAssembly and other particular architectures
pub usingnamespace capy.cross_platform;

// This is awful but its the only way i can think of passing these
var CURR_FILE: ?*osufile.OsuFile = null;
var OPTION_FLAG: u8 = 0;
var CURR_FILE_LABEL: ?*capy.Label = null;
var PREADER: pread.ProcReader = undefined;
const SETTINGS_LOCATIONS = [_]usize{ 5, 6, 7, 8, 9, 10, 12 }; // Edit this when adding more boolean vars to the settings menu

fn undoButton(btn: *capy.Button) anyerror!void {
    _ = btn;
    try wrapper.undoLast(CURR_FILE, .undo);
}

fn redoButton(btn: *capy.Button) anyerror!void {
    _ = btn;
    try wrapper.undoLast(CURR_FILE, .redo);
}

fn preaderBtn(btn: *capy.Button) anyerror!void {
    //defer PREADER.deinit(); //test
    const parent_wgt = btn.*.getParent().?.as(capy.Container);
    var params = [_][]u8{undefined} ** 16;
    params[15] = try std.heap.page_allocator.alloc(u8, 1);
    defer for (0..10) |k| std.heap.page_allocator.free(params[k]);

    //const tmp = try wrapper.preadTest(&PREADER); // THIS IS STUPID AND NOT NEEDED
    const beatmap = try PREADER.toStr();
    defer std.heap.page_allocator.free(beatmap);

    var flag: u8 = 0x1;
    for (SETTINGS_LOCATIONS) |l| {
        if (((try parent_wgt.*.getChildAt(l)).as(capy.CheckBox).*.checked.get())) OPTION_FLAG |= flag; // Nightmare fuel
        flag <<= 1;
    }

    // ...
    // I
    // LOVE
    // WCHARS - TODO: this needs to be fixed as it causes errors w/ non-ascii filepaths

    var strlen: usize = 0;
    for (beatmap) |c| {
        switch (c) {
            0 => continue,
            else => strlen += 1,
        }
    }
    params[1] = try std.heap.page_allocator.alloc(u8, strlen);
    var i: usize = 0;
    for (beatmap) |c| {
        switch (c) {
            0 => continue,
            else => {
                params[1][i] = c;
                i += 1;
            },
        }
    }

    // That should fix the wchar problem
    // ... fuck you bill

    // Call this to init the target
    CURR_FILE = try wrapper.initTargetFile(params);

    if (CURR_FILE) |fp| {
        // This most likely leaks memory... I can't find a way to fix it...
        CURR_FILE_LABEL.?.*.text.set(try std.fmt.allocPrintZ(std.heap.page_allocator, "Editing: {s} - {s} | [{s}]", .{ fp.metadata.artist, fp.metadata.title, fp.metadata.version }));
    }
}

fn buttonClick(btn: *capy.Button) anyerror!void {
    const parent_wgt = btn.*.getParent().?.as(capy.Container);
    const parent_name = parent_wgt.widget.?.name.get() orelse unreachable;

    var i: usize = 2;
    var p: usize = 1;
    var max: usize = 0;

    // params[0] is always the parent name, params[15] is always the option flag
    var params = [_][]u8{undefined} ** 16;
    params[15] = try std.heap.page_allocator.alloc(u8, 1);
    defer {
        for (0..params.len) |k| std.heap.page_allocator.free(params[k]);
    }

    switch (parent_name[0] - '0') {
        0 => {
            max = 2;

            // TODO: Test this shit
            var flag: u8 = 0x1;
            for (SETTINGS_LOCATIONS) |l| {
                if (((try parent_wgt.*.getChildAt(l)).as(capy.CheckBox).*.checked.get())) {
                    OPTION_FLAG |= flag; // Nightmare fuel
                }
                flag <<= 1;
            }
        },
        1 => {
            switch (parent_name[1] - '0') {
                0, 1, 4, 5 => max = 4,
                2 => max = 6,
                3 => max = 6,
                else => unreachable,
            }
        },
        2 => {
            switch (parent_name[1] - '0') {
                0, 1, 2 => max = 4,
                else => unreachable,
            }
        },
        3 => {
            switch (parent_name[1] - '0') {
                0, 1 => max = 6,
                2 => max = 10,
                else => unreachable,
            }
        },
        else => unreachable,
    }

    params[0] = try std.heap.page_allocator.alloc(u8, parent_name.len);
    @memcpy(params[0], parent_name);

    params[15][0] = OPTION_FLAG; // This should always be the last param

    // Awful and slow way of doing something simple
    while (i <= max) : (i += 1) {
        // I dont really know a faster way of doing this....
        if ((try parent_wgt.*.getChildAt(i)).is(capy.Label)) {
            continue; // Skip any labels
        } else if ((try parent_wgt.*.getChildAt(i)).is(capy.Container)) {
            const row_wgt = (try parent_wgt.*.getChildAt(i)).as(capy.Container);

            for (0..(row_wgt.widget.?.name.get() orelse unreachable).len) |j| {
                const text_out = switch ((row_wgt.*.widget.?.name.get() orelse unreachable)[j]) { // This is so ass
                    'T' => (try row_wgt.*.getChildAt(j)).as(capy.TextField).*.text.get(),
                    'C' => if ((try row_wgt.*.getChildAt(j)).as(capy.CheckBox).*.checked.get()) @constCast("1") else @constCast("0"),
                    'L' => continue, // just skip any label fields
                    else => unreachable,
                };

                params[p] = try std.heap.page_allocator.alloc(u8, text_out.len);
                @memcpy(params[p], text_out);
                p += 1;
            }
        } else if ((try parent_wgt.*.getChildAt(i)).is(capy.CheckBox)) {
            const cb_wgt = (try parent_wgt.*.getChildAt(i)).as(capy.CheckBox);

            const text_out = if (cb_wgt.*.checked.get()) @constCast("1") else @constCast("0"); // Hopefully this works??
            params[p] = try std.heap.page_allocator.alloc(u8, text_out.len);
            @memcpy(params[p], text_out);
            p += 1;
        } else {
            const text_wgt = (try parent_wgt.*.getChildAt(i)).as(capy.TextField);

            const text_out = text_wgt.*.text.get();
            params[p] = try std.heap.page_allocator.alloc(u8, text_out.len);
            @memcpy(params[p], text_out);
            p += 1;
        }
    }
    // Previous implementation
    //while(i <= max) : (i += 2) {
    //const text_wgt = (try parent_wgt.*.getChildAt(i)).as(capy.TextField);
    //const text_out = text_wgt.*.text.get();
    //params[p] = try std.heap.page_allocator.alloc(u8, text_out.len);
    //@memcpy(params[p], text_out);
    //p += 1;
    //}

    switch (parent_name[0] - '0') {
        0 => {
            CURR_FILE = try wrapper.initTargetFile(params);
            if (CURR_FILE) |fp| {
                // This most likely leaks memory... I can't find a way to fix it...
                CURR_FILE_LABEL.?.*.text.set(try std.fmt.allocPrintZ(std.heap.page_allocator, "Editing: {s} - {s} | [{s}]", .{ fp.metadata.artist, fp.metadata.title, fp.metadata.version }));
            }
        },
        1 => {
            switch (parent_name[1] - '0') {
                0...5 => try wrapper.applySVFn(CURR_FILE, params),
                else => unreachable,
            }
        },
        2 => {
            switch (parent_name[1] - '0') {
                0...2 => try wrapper.applyHObjFn(CURR_FILE, params),
                else => unreachable,
            }
        },
        3 => {
            switch (parent_name[1] - '0') {
                0...2 => try wrapper.applyBarlineFn(CURR_FILE, params),
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

pub fn main() !void {
    try capy.backend.init();

    var window = try capy.Window.init();
    defer window.deinit();

    const cont_lin = try capy.column(.{ .name = "10" }, .{
        capy.button(.{ .label = "Apply", .onclick = @ptrCast(&buttonClick) }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{ // the name field is just going to be used as a label for what is in the section
            capy.label(.{ .alignment = .Left, .text = "Start Time" }),
            capy.label(.{ .alignment = .Left, .text = "End Time" }),
        }),
        capy.row(.{ .name = "TT", .expand = .Fill }, .{
            capy.textField(.{}),
            capy.textField(.{}),
        }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{ // the name field is just going to be used as a label for what is in the section
            capy.label(.{ .alignment = .Left, .text = "Start Value" }),
            capy.label(.{ .alignment = .Left, .text = "End Value" }),
        }),
        capy.row(.{ .name = "TT", .expand = .Fill }, .{
            capy.textField(.{}),
            capy.textField(.{}),
        }),
        //capy.label(.{ .alignment = .Left, .text = "Start Time" }),
        //capy.textField(.{}),
        //capy.label(.{ .alignment = .Left, .text = "End Time" }),
        //capy.textField(.{}),
        //capy.label(.{ .alignment = .Left, .text = "Start Value" }),
        //capy.textField(.{}),
        //capy.label(.{ .alignment = .Left, .text = "End Value" }),
        //capy.textField(.{}),
        //capy.checkBox(.{ .label = "Bounded Random" }),
        //capy.label(.{ .alignment = .Left, .text = "Variance" }),
        //capy.textField(.{ .readOnly = true }),
    });

    const cont_exp = try capy.column(.{ .name = "11" }, .{
        capy.button(.{ .label = "Apply", .onclick = @ptrCast(&buttonClick) }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{
            capy.label(.{ .alignment = .Left, .text = "Start Time" }),
            capy.label(.{ .alignment = .Left, .text = "End Time" }),
        }),
        capy.row(.{ .name = "TT", .expand = .Fill }, .{
            capy.textField(.{}),
            capy.textField(.{}),
        }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{
            capy.label(.{ .alignment = .Left, .text = "Start Value" }),
            capy.label(.{ .alignment = .Left, .text = "End Value" }),
        }),
        capy.row(.{ .name = "TT", .expand = .Fill }, .{
            capy.textField(.{}),
            capy.textField(.{}),
        }),
        //capy.checkBox(.{ .label = "Bounded Random" }),
    });

    const cont_sin = try capy.column(.{ .name = "12" }, .{
        capy.button(.{ .label = "Apply", .onclick = @ptrCast(&buttonClick) }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{
            capy.label(.{ .alignment = .Left, .text = "Start Time" }),
            capy.label(.{ .alignment = .Left, .text = "End Time" }),
        }),
        capy.row(.{ .name = "TT", .expand = .Fill }, .{
            capy.textField(.{}),
            capy.textField(.{}),
        }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{
            capy.label(.{ .alignment = .Left, .text = "Lower Bound" }),
            capy.label(.{ .alignment = .Left, .text = "Upper Bound" }),
        }),
        capy.row(.{ .name = "TT", .expand = .Fill }, .{
            capy.textField(.{}),
            capy.textField(.{}),
        }),
        capy.label(.{ .alignment = .Left, .text = "Cycles" }),
        capy.textField(.{}),
        //capy.label(.{ .alignment = .Left, .text = "Cycles" }),
        //capy.textField(.{}),
        //capy.checkBox(.{ .label = "Bounded Random" }),
    });

    const cont_bez = try capy.column(.{ .name = "13" }, .{
        capy.button(.{ .label = "Apply", .onclick = @ptrCast(&buttonClick) }),
        capy.label(.{ .alignment = .Left, .text = "Start Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "End Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "Start X" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "Start Y" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "End X" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "End Y" }),
        capy.textField(.{}),
        //capy.checkBox(.{ .label = "Bounded Random" }),
    });

    const cont_adj = try capy.column(.{ .name = "14" }, .{
        capy.button(.{ .label = "Apply", .onclick = @ptrCast(&buttonClick) }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{
            capy.label(.{ .alignment = .Left, .text = "Start Time" }),
            capy.label(.{ .alignment = .Left, .text = "End Time" }),
        }),
        capy.row(.{ .name = "TT", .expand = .Fill }, .{
            capy.textField(.{}),
            capy.textField(.{}),
        }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{
            capy.label(.{ .alignment = .Left, .text = "Lower Bound" }),
            capy.label(.{ .alignment = .Left, .text = "Upper Bound" }),
        }),
        capy.row(.{ .name = "TT", .expand = .Fill }, .{
            capy.textField(.{}),
            capy.textField(.{}),
        }),
    });

    const cont_lin_vol = try capy.column(.{ .name = "15" }, .{
        capy.button(.{ .label = "Apply", .onclick = @ptrCast(&buttonClick) }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{
            capy.label(.{ .alignment = .Left, .text = "Start Time" }),
            capy.label(.{ .alignment = .Left, .text = "End Time" }),
        }),
        capy.row(.{ .name = "TT", .expand = .Fill }, .{
            capy.textField(.{}),
            capy.textField(.{}),
        }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{
            capy.label(.{ .alignment = .Left, .text = "Start Volume" }),
            capy.label(.{ .alignment = .Left, .text = "End Volume" }),
        }),
        capy.row(.{ .name = "TT", .expand = .Fill }, .{
            capy.textField(.{}),
            capy.textField(.{}),
        }),
    });

    //***************************************************
    //  HIT OBJECTS
    //***************************************************

    const cont_snap_to = try capy.column(.{ .name = "20" }, .{
        capy.button(.{ .label = "Apply", .onclick = @ptrCast(&buttonClick) }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{
            capy.label(.{ .alignment = .Left, .text = "Start Time" }),
            capy.label(.{ .alignment = .Left, .text = "End Time" }),
        }),
        capy.row(.{ .name = "TT", .expand = .Fill }, .{
            capy.textField(.{}),
            capy.textField(.{}),
        }),
        capy.label(.{ .alignment = .Left, .text = "List of snappings" }),
        capy.textField(.{ .text = "4, 6, 8, 12" }),
    });

    const cont_to_barline = try capy.column(.{ .name = "21" }, .{
        capy.button(.{ .label = "Apply", .onclick = @ptrCast(&buttonClick) }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{
            capy.label(.{ .alignment = .Left, .text = "Start Time" }),
            capy.label(.{ .alignment = .Left, .text = "End Time" }),
        }),
        capy.row(.{ .name = "TT", .expand = .Fill }, .{
            capy.textField(.{}),
            capy.textField(.{}),
        }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{
            capy.label(.{ .alignment = .Left, .text = "Lines per D" }),
            capy.label(.{ .alignment = .Left, .text = "Lines per K" }),
        }),
        capy.row(.{ .name = "TT", .expand = .Fill }, .{
            capy.textField(.{}),
            capy.textField(.{}),
        }),
    });

    const cont_to_unhittable = try capy.column(.{ .name = "22" }, .{
        capy.button(.{ .label = "Apply", .onclick = @ptrCast(&buttonClick) }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{
            capy.label(.{ .alignment = .Left, .text = "Start Time" }),
            capy.label(.{ .alignment = .Left, .text = "End Time" }),
        }),
        capy.row(.{ .name = "TT", .expand = .Fill }, .{
            capy.textField(.{}),
            capy.textField(.{}),
        }),
        capy.label(.{ .alignment = .Left, .text = "Offset" }),
        capy.textField(.{}),
    });

    //***************************************************
    //  BARLINES
    //***************************************************

    const cont_static_rand_barline = try capy.column(.{ .name = "30" }, .{
        capy.button(.{ .label = "Apply", .onclick = @ptrCast(&buttonClick) }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{
            capy.label(.{ .alignment = .Left, .text = "Start Time" }),
            capy.label(.{ .alignment = .Left, .text = "End Time" }),
        }),
        capy.row(.{ .name = "TT", .expand = .Fill }, .{
            capy.textField(.{}),
            capy.textField(.{}),
        }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{
            capy.label(.{ .alignment = .Left, .text = "Min BPM" }),
            capy.label(.{ .alignment = .Left, .text = "Max BPM" }),
        }),
        capy.row(.{ .name = "TT", .expand = .Fill }, .{
            capy.textField(.{}),
            capy.textField(.{}),
        }),
        capy.label(.{ .alignment = .Left, .text = "Percent Chance" }),
        capy.textField(.{}),
        capy.checkBox(.{ .label = "Escape out notes in this section", .checked = true }),
    });

    const cont_linear_60k_bl = try capy.column(.{ .name = "31" }, .{
        capy.button(.{ .label = "Apply", .onclick = @ptrCast(&buttonClick) }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{
            capy.label(.{ .alignment = .Left, .text = "Start Time" }),
            capy.label(.{ .alignment = .Left, .text = "End Time" }),
        }),
        capy.row(.{ .name = "TT", .expand = .Fill }, .{
            capy.textField(.{}),
            capy.textField(.{}),
        }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{
            capy.label(.{ .alignment = .Left, .text = "Starting Lines" }),
            capy.label(.{ .alignment = .Left, .text = "Ending Lines" }),
        }),
        capy.row(.{ .name = "TT", .expand = .Fill }, .{
            capy.textField(.{}),
            capy.textField(.{}),
        }),
        capy.label(.{ .alignment = .Left, .text = "Resolution" }),
        capy.textField(.{}),
        capy.checkBox(.{ .label = "Escape out notes in this section", .checked = true }),
    });

    const cont_60k_bl_creator = try capy.column(.{ .name = "32", .expand = .No }, .{
        capy.button(.{ .label = "Apply", .onclick = @ptrCast(&buttonClick) }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{ // the name field is just going to be used as a label for what is in the section
            capy.label(.{ .alignment = .Left, .text = "Start Time" }),
            capy.label(.{ .alignment = .Left, .text = "End Time" }),
        }),
        capy.row(.{ .name = "TT", .expand = .Fill }, .{
            capy.textField(.{}),
            capy.textField(.{}),
        }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{
            capy.label(.{ .alignment = .Left, .text = "Starting lines" }),
            capy.label(.{ .alignment = .Left, .text = "Ending lines" }),
        }),
        capy.row(.{ .name = "TTC", .expand = .Fill }, .{
            capy.textField(.{}),
            capy.textField(.{}),
            capy.checkBox(.{ .label = "Enable", .checked = false }),
        }),
        capy.row(.{ .name = "LL", .expand = .Fill }, .{
            capy.label(.{ .alignment = .Left, .text = "Starting meter" }),
            capy.label(.{ .alignment = .Left, .text = "Ending meter" }),
        }),
        capy.row(.{ .name = "TTC", .expand = .Fill }, .{
            capy.textField(.{ .text = "1" }),
            capy.textField(.{ .text = "1" }),
            capy.checkBox(.{ .label = "Enable", .checked = false }),
        }),
        capy.label(.{ .alignment = .Left, .text = "Resolution" }),
        capy.textField(.{ .text = "16" }), // This refers to the snapping which the notes are at
        capy.checkBox(.{ .label = "Escape any notes in this section", .checked = true }),
        capy.checkBox(.{ .label = "Omit last barline", .checked = false }),
    });
    //const cont_barlines_tba = try capy.column(.{ .name = "30" }, .{ // PLACEHOLDER
    //    capy.label(.{ .alignment = .Center, .text = "Coming soon (tm)" }),
    //});

    //***************************************************
    //  SETTINGS
    //***************************************************

    // IDEA: maybe have this save to a settings.zon file?
    const cont_set = try capy.column(.{ .name = "0" }, .{
        capy.button(.{ .label = "Apply", .onclick = @ptrCast(&buttonClick) }),
        capy.label(.{ .alignment = .Left, .text = "osu! Song directory path" }),
        capy.textField(.{}),
        capy.button(.{ .label = "Detect", .onclick = @ptrCast(&preaderBtn) }), // TODO: Feel like this would be nicer if it was beside the textbox ^
        capy.label(.{ .alignment = .Left, .text = "SV Settings" }),
        capy.checkBox(.{ .label = "Snap SV to notes", .checked = true }),
        capy.checkBox(.{ .label = "Normalize SV over BPM changes", .checked = true }),
        capy.checkBox(.{ .label = "Overwrite previous SV", .checked = false }),
        capy.checkBox(.{ .label = "Add SV to all timing points in the effect", .checked = false }),
        capy.checkBox(.{ .label = "Add SV to all barlines in the effect", .checked = false }), // Will have to get offset of each timing point and then find every barline that would exist in it
        capy.checkBox(.{ .label = "Points inherit effects from previous points", .checked = false }), // Will have to get offset of each timing point and then find every barline that would exist in it
        capy.label(.{ .alignment = .Left, .text = "File Settings" }),
        capy.checkBox(.{ .label = "Automatically create backup files", .checked = true }),
        capy.label(.{ .alignment = .Left, .text = "Ver 0.0.1 " }),
    });

    //***************************************************
    //  UI STRUCTURE
    //***************************************************

    CURR_FILE_LABEL = capy.label(.{ .alignment = .Left, .text = "No file selected..." });
    const header_bar = capy.row(.{ .name = "z", .expand = .No, .spacing = 5 }, .{
        capy.expanded(CURR_FILE_LABEL orelse unreachable),
    });

    const global_opt_bar = capy.row(.{ .name = "y", .expand = .No, .spacing = 5 }, .{
        capy.button(.{ .label = "Redo", .onclick = @ptrCast(&redoButton) }),
        capy.button(.{ .label = "Undo", .onclick = @ptrCast(&undoButton) }),
    });

    const tab_lin = capy.tab(.{ .label = "Linear" }, cont_lin);
    const tab_exp = capy.tab(.{ .label = "Exponential" }, cont_exp);
    const tab_sin = capy.tab(.{ .label = "Sine" }, cont_sin);
    const tab_bez = capy.tab(.{ .label = "Bezier" }, cont_bez);
    const tab_adj = capy.tab(.{ .label = "Adjustments" }, cont_adj);
    const tab_lin_vol = capy.tab(.{ .label = "Linear Volume" }, cont_lin_vol);

    const tab_snap = capy.tab(.{ .label = "Auto-snap" }, cont_snap_to);
    const tab_to_bar = capy.tab(.{ .label = "Note to barline" }, cont_to_barline);
    const tab_to_unhit = capy.tab(.{ .label = "Unhittable note" }, cont_to_unhittable);

    const tab_static_rand_bl = capy.tab(.{ .label = "Random barline" }, cont_static_rand_barline);
    const tab_linear_60k_bl = capy.tab(.{ .label = "Linear 60k barlines" }, cont_linear_60k_bl);
    const tab_60k_bl_creator = capy.tab(.{ .label = "60k barline creator" }, cont_60k_bl_creator);

    const tab_cont_sv = capy.tabs(.{ tab_lin, tab_exp, tab_sin, tab_bez, tab_adj, tab_lin_vol });
    const tab_cont_hobj = capy.tabs(.{ tab_snap, tab_to_bar, tab_to_unhit });
    const tab_cont_barlines = capy.tabs(.{ tab_static_rand_bl, tab_linear_60k_bl, tab_60k_bl_creator });

    const tab_cont_1 = capy.tab(.{ .label = "Slider Velocity" }, tab_cont_sv);
    const tab_cont_2 = capy.tab(.{ .label = "Hit Objects" }, tab_cont_hobj);
    const tab_cont_3 = capy.tab(.{ .label = "Barlines" }, tab_cont_barlines);
    const tab_cont_set = capy.tab(.{ .label = "Settings" }, cont_set);

    const main_tab_cont = capy.tabs(.{ tab_cont_1, tab_cont_2, tab_cont_3, tab_cont_set });

    var main_cont: *capy.Container = undefined;
    switch (builtin.os.tag) {
        .linux => {
            //const TEST_IMG = capy.image(.{ .url = "file:///home/koishi/Programming/Zig/SVBUDDY/test_files/svbuddy.png", .scaling = .Fit }); // TODO: HOW THE FUCK DO I GET THIS TO JUST READ A RELATIVE PATH FML!!!!!!!!
            main_cont = try capy.column(.{ .expand = .No, .spacing = 5 }, .{
                header_bar,
                global_opt_bar,
                //TEST_IMG, - i dont think this is really needed... id say make it the map bg but i dont think this does jpg
                main_tab_cont,
            });
        },
        else => {
            main_cont = try capy.column(.{ .expand = .No, .spacing = 5 }, .{
                header_bar,
                global_opt_bar,
                main_tab_cont,
            });
        },
    }

    window.setPreferredSize(600, 640); // May need to be expanded in the future

    window.setTitle("SVBuddy");

    try window.set(main_cont);

    window.show();
    capy.runEventLoop();
}
