// "My hope is that this code is so awful I'm never allowed to write UI code again."
const std = @import("std");
const capy = @import("capy");
const osufile = @import("./core/osufileio.zig");
const com = @import("./util/common.zig");
const wrapper = @import("./util/backend_wrappers.zig");
const builtin = @import("builtin");

//TMP
const sv = @import("./core/libsv.zig");
const hobj = @import("./core/hitobj.zig");

//=============================================
// TODO
//=============================================
//  * IMPLEMENT VOLUME CHANGES
//  * FIX THE PROBLEM WITH VALUES 3,4,6,8 DEFAULTING TO 170
//  * ADD KIAI CHECKBOX / AUTO KIAI ON AND OFF | SAME COULD GO FOR VOLUME
//  * IMPLEMENT SONG PICKER W/ SOME KIND OF FUZZY SEARCH
//=============================================
//  VERY BIG TODO
//=============================================
//  * MAKE THIS PROGRAM STORE CHANGES IN A DIFF FORMAT S.T. YOU CAN UNDO AND REDO EFFECTS
//  * SWITCH ALL PAGE_ALLOCATORS TO GeneralPurposeAllocators
//=============================================
// LAYOUT IDEA
//=============================================
// -----------on startup
//      top: column container w/ search bar and scrollable menu for song select
//              *  RESEARCH: look if you can read process data and find the current song that way
//      bottom: settings tab
// -----------post song select
//      top: either a graph showing sv and bpm changes throughout the map
//           or some kind of visual helper for the effect being applied (this might just become its own little pop up window)
//      bottom: hopefully a better interface than what i have now.
//              *  RESEARCH: look at other tools for inspiration
//=============================================

// This is required for your app to build to WebAssembly and other particular architectures
pub usingnamespace capy.cross_platform;

// This is awful but its the only way i can think of passing these
var CURR_FILE: ?*osufile.OsuFile = null;
var OPTION_FLAG: u8 = 0;
var CURR_FILE_LABEL: ?*capy.Label = null;

fn buttonClick(btn: *capy.Button) anyerror!void {
    const parent_wgt = btn.*.getParent().?.as(capy.Container);
    const parent_name = parent_wgt.widget.?.name.get() orelse unreachable;

    var i: usize = 2;
    var p: usize = 1;
    var max: usize = 0;

    // params[0] is always the parent name, params[9] is always the option flag
    var params = [_][]u8{undefined} ** 10;
    params[9] = try std.heap.page_allocator.alloc(u8, 1);
    defer {
        for (0..10) |k| std.heap.page_allocator.free(params[k]);
    }

    switch (parent_name[0] - '0') {
        0 => { // 4-9,11
            max = 2;

            // Get the status of all options in the settings menu
            // TODO: FUCK YOU FOR DOING THIS YOU CAN DO BETTER... ALSO MAKE AN ENUM FOR THIS OR SOMETHING
            const check_wg = (try parent_wgt.*.getChildAt(4)).as(capy.CheckBox);
            const check = check_wg.*.checked.get();
            const check_wg2 = (try parent_wgt.*.getChildAt(5)).as(capy.CheckBox);
            const check2 = check_wg2.*.checked.get();
            const check_wg3 = (try parent_wgt.*.getChildAt(6)).as(capy.CheckBox);
            const check3 = check_wg3.*.checked.get();
            const check_wg4 = (try parent_wgt.*.getChildAt(7)).as(capy.CheckBox);
            const check4 = check_wg4.*.checked.get();
            const check_wg5 = (try parent_wgt.*.getChildAt(8)).as(capy.CheckBox);
            const check5 = check_wg5.*.checked.get();
            const check_wg6 = (try parent_wgt.*.getChildAt(9)).as(capy.CheckBox);
            const check6 = check_wg6.*.checked.get();
            const check_wg7 = (try parent_wgt.*.getChildAt(11)).as(capy.CheckBox);
            const check7 = check_wg7.*.checked.get();

            if (check) OPTION_FLAG |= 0x1;
            if (check2) OPTION_FLAG |= 0x2;
            if (check3) OPTION_FLAG |= 0x4;
            if (check4) OPTION_FLAG |= 0x8;
            if (check5) OPTION_FLAG |= 0x10;
            if (check6) OPTION_FLAG |= 0x20;
            if (check7) OPTION_FLAG |= 0x40;
            //if (check8) OPTION_FLAG |= 0x80;
        },
        1 => {
            switch (parent_name[1] - '0') {
                0, 1, 4 => max = 8,
                2 => max = 10,
                3 => max = 12,
                else => unreachable,
            }
        },
        2 => {
            switch (parent_name[1] - '0') {
                0 => max = 6,
                else => unreachable,
            }
        },
        else => unreachable,
    }

    params[0] = try std.heap.page_allocator.alloc(u8, parent_name.len);
    @memcpy(params[0], parent_name);
    std.debug.print("A:{s}:{s}\n", .{ parent_name, params[0] });

    params[9][0] = OPTION_FLAG; // This should always be the last param

    while (i <= max) : (i += 2) {
        const text_wgt = (try parent_wgt.*.getChildAt(i)).as(capy.TextField);
        const text_out = text_wgt.*.text.get();
        params[p] = try std.heap.page_allocator.alloc(u8, text_out.len);
        @memcpy(params[p], text_out);
        p += 1;
    }
    std.debug.print("B\n", .{});

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
                0, 1, 2, 3, 4 => try wrapper.applySVFn(CURR_FILE, params),
                else => unreachable,
            }
        },
        2 => {
            std.debug.print("C\n", .{});
            switch (parent_name[1] - '0') {
                0, 1, 2 => try wrapper.applyHObjFn(CURR_FILE, params),
                else => unreachable,
            }
        },
        3 => {
            // TO BE IMPLEMENTED
            std.debug.print("ERROR: Section not implemented yet.\n", .{});
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
        capy.label(.{ .alignment = .Left, .text = "Start Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "End Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "Start Value" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "End Value" }),
        capy.textField(.{}),
        //capy.checkBox(.{ .label = "Bounded Random" }),
        //capy.label(.{ .alignment = .Left, .text = "Variance" }),
        //capy.textField(.{ .readOnly = true }),
    });

    const cont_exp = try capy.column(.{ .name = "11" }, .{
        capy.button(.{ .label = "Apply", .onclick = @ptrCast(&buttonClick) }),
        capy.label(.{ .alignment = .Left, .text = "Start Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "End Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "Start Value" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "End Value" }),
        capy.textField(.{}),
        //capy.checkBox(.{ .label = "Bounded Random" }),
    });

    const cont_sin = try capy.column(.{ .name = "12" }, .{
        capy.button(.{ .label = "Apply", .onclick = @ptrCast(&buttonClick) }),
        capy.label(.{ .alignment = .Left, .text = "Start Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "End Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "Lower Bound" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "Upper Bound" }),
        capy.textField(.{}),
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
        capy.label(.{ .alignment = .Left, .text = "Start Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "End Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "Lower Bound" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "Upper Bound" }),
        capy.textField(.{}),
    });

    //***************************************************
    //  HIT OBJECTS
    //***************************************************

    const cont_snap_to = try capy.column(.{ .name = "20" }, .{
        capy.button(.{ .label = "Apply", .onclick = @ptrCast(&buttonClick) }),
        capy.label(.{ .alignment = .Left, .text = "Start Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "End Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "List of snappings" }),
        capy.textField(.{ .text = "4, 6, 8, 12" }),
        //capy.textField(.{}),
    });

    const cont_to_barline = try capy.column(.{ .name = "21" }, .{
        capy.button(.{ .label = "Apply", .onclick = @ptrCast(&buttonClick) }),
        capy.label(.{ .alignment = .Left, .text = "Start Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "End Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "Lines per D" }),
        capy.textField(.{ .text = "" }),
        capy.label(.{ .alignment = .Left, .text = "Lines per K" }),
        capy.textField(.{ .text = "" }),
    });

    const cont_to_unhittable = try capy.column(.{ .name = "22" }, .{
        capy.button(.{ .label = "Apply", .onclick = @ptrCast(&buttonClick) }),
        capy.label(.{ .alignment = .Left, .text = "Start Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "End Time" }),
        capy.textField(.{}),
    });

    //***************************************************
    //  GIMMICK
    //***************************************************

    const cont_gimmick_tba = try capy.column(.{ .name = "30" }, .{ // PLACEHOLDER
        capy.label(.{ .alignment = .Center, .text = "Coming soon (tm)" }),
    });

    //***************************************************
    //  SETTINGS
    //***************************************************

    // IDEA: maybe have this save to a settings.zon file?
    const cont_set = try capy.column(.{ .name = "0" }, .{
        capy.button(.{ .label = "Apply", .onclick = @ptrCast(&buttonClick) }),
        capy.label(.{ .alignment = .Left, .text = "osu! Song directory path" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "SV Settings" }),
        capy.checkBox(.{ .label = "Snap SV to notes", .checked = true }),
        capy.checkBox(.{ .label = "Normalize SV over BPM changes", .checked = true }),
        capy.checkBox(.{ .label = "Overwrite ALL previous SV (this includes uninherited points)", .checked = false }),
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

    const tab_lin = capy.tab(.{ .label = "Linear" }, cont_lin);
    const tab_exp = capy.tab(.{ .label = "Exponential" }, cont_exp);
    const tab_sin = capy.tab(.{ .label = "Sine" }, cont_sin);
    const tab_bez = capy.tab(.{ .label = "Bezier" }, cont_bez);
    const tab_adj = capy.tab(.{ .label = "Adjustments" }, cont_adj);

    const tab_snap = capy.tab(.{ .label = "Auto-snap" }, cont_snap_to);
    const tab_to_bar = capy.tab(.{ .label = "Note to barline" }, cont_to_barline);
    const tab_to_unhit = capy.tab(.{ .label = "Unhittable note" }, cont_to_unhittable);

    const tab_cont_sv = capy.tabs(.{ tab_lin, tab_exp, tab_sin, tab_bez, tab_adj });
    const tab_cont_hobj = capy.tabs(.{ tab_snap, tab_to_bar, tab_to_unhit });

    const tab_cont_1 = capy.tab(.{ .label = "Slider Velocity" }, tab_cont_sv);
    const tab_cont_2 = capy.tab(.{ .label = "Hit Objects" }, tab_cont_hobj);
    const tab_cont_set = capy.tab(.{ .label = "Settings" }, cont_set);
    const tab_cont_gimmick = capy.tab(.{ .label = "Gimmicks" }, cont_gimmick_tba);

    const main_tab_cont = capy.tabs(.{ tab_cont_1, tab_cont_2, tab_cont_gimmick, tab_cont_set });

    var main_cont: *capy.Container = undefined;
    switch (builtin.os.tag) {
        .linux => {
            const TEST_IMG = capy.image(.{ .url = "file:///home/koishi/Programming/Zig/SVUI/test_files/svbuddy.png", .scaling = .Fit });
            main_cont = try capy.column(.{ .expand = .No, .spacing = 5 }, .{
                CURR_FILE_LABEL orelse unreachable, // This shouldn't fail
                TEST_IMG,
                main_tab_cont,
            });
        },
        else => { // Im not sure if images are supported on other platforms
            main_cont = try capy.column(.{ .expand = .No, .spacing = 5 }, .{
                CURR_FILE_LABEL orelse unreachable, // This shouldn't fail
                main_tab_cont,
            });
        },
    }

    window.setPreferredSize(240, 320);

    window.setTitle("SV Buddy");

    try window.set(main_cont);

    window.show();

    capy.runEventLoop();
}
