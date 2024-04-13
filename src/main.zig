// "My hope is that this code is so awful I'm never allowed to write UI code again."
const std = @import("std");
const capy = @import("capy");
const osufile = @import("./core/osufileio.zig");
const com = @import("./util/common.zig");
const wrapper = @import("./util/backend_wrappers.zig");

//=============================================
// TODO
//=============================================
//  * IMPLEMENT VOLUME CHANGES
//  * FIX THE PROBLEM WITH VALUES 3,4,6,8 DEFAULTING TO 170
//  * ADD KIAI CHECKBOX / AUTO KIAI ON AND OFF | SAME COULD GO FOR VOLUME
//  * IMPLEMENT SONG PICKER W/ SOME KIND OF FUZZY SEARCH
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
        1, 2, 5 => max = 8,
        3 => max = 10,
        4 => max = 12,
        6 => { // 4,5,6,8
            max = 2;

            // Get the status of all options in the settings menu
            // TODO: FUCK YOU FOR DOING THIS YOU CAN DO BETTER
            const check_wg = (try parent_wgt.*.getChildAt(4)).as(capy.CheckBox);
            const check = check_wg.*.checked.get();
            const check_wg2 = (try parent_wgt.*.getChildAt(5)).as(capy.CheckBox);
            const check2 = check_wg2.*.checked.get();
            const check_wg3 = (try parent_wgt.*.getChildAt(6)).as(capy.CheckBox);
            const check3 = check_wg3.*.checked.get();
            const check_wg4 = (try parent_wgt.*.getChildAt(8)).as(capy.CheckBox);
            const check4 = check_wg4.*.checked.get();

            if (check) OPTION_FLAG |= 0x1;
            if (check2) OPTION_FLAG |= 0x2;
            if (check3) OPTION_FLAG |= 0x4;
            if (check4) OPTION_FLAG |= 0x8;
        },
        else => unreachable,
    }

    params[0] = try std.heap.page_allocator.alloc(u8, parent_name.len);
    @memcpy(params[0], parent_name);

    params[9][0] = OPTION_FLAG; // This should always be the last param

    while (i <= max) : (i += 2) {
        const text_wgt = (try parent_wgt.*.getChildAt(i)).as(capy.TextField);
        const text_out = text_wgt.*.text.get();
        params[p] = try std.heap.page_allocator.alloc(u8, text_out.len);
        @memcpy(params[p], text_out);
        p += 1;
    }

    switch (parent_name[0] - '0') {
        1, 2, 3, 5 => try wrapper.applyFn(CURR_FILE, params),
        6 => {
            CURR_FILE = try wrapper.initTargetFile(params);
            if (CURR_FILE) |fp| {
                // This most likely leaks memory... I can't find a way to fix it...
                CURR_FILE_LABEL.?.*.text.set(try std.fmt.allocPrintZ(std.heap.page_allocator, "Editing: {s} - {s} | [{s}]", .{ fp.metadata.artist, fp.metadata.title, fp.metadata.version }));
            }
        },
        else => unreachable,
    }
}

pub fn main() !void {
    try capy.backend.init();

    var window = try capy.Window.init();
    defer window.deinit();

    const cont_lin = try capy.column(.{ .name = "1" }, .{
        capy.button(.{ .label = "Apply Effect", .onclick = @ptrCast(&buttonClick) }),
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

    const cont_exp = try capy.column(.{ .name = "2" }, .{
        capy.button(.{ .label = "Apply Effect", .onclick = @ptrCast(&buttonClick) }),
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

    const cont_sin = try capy.column(.{ .name = "3" }, .{
        capy.button(.{ .label = "Apply Effect", .onclick = @ptrCast(&buttonClick) }),
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

    //const cont_bez = try capy.column(.{ .name = "4" }, .{
    //    capy.button(.{ .label = "Apply Effect", .onclick = @ptrCast(&buttonClick) }),
    //    capy.label(.{ .alignment = .Left, .text = "Start Time" }),
    //    capy.textField(.{}),
    //    capy.label(.{ .alignment = .Left, .text = "End Time" }),
    //    capy.textField(.{}),
    //    capy.label(.{ .alignment = .Left, .text = "Start X" }),
    //    capy.textField(.{}),
    //    capy.label(.{ .alignment = .Left, .text = "Start Y" }),
    //    capy.textField(.{}),
    //    capy.label(.{ .alignment = .Left, .text = "End X" }),
    //    capy.textField(.{}),
    //    capy.label(.{ .alignment = .Left, .text = "End Y" }),
    //    capy.textField(.{}),
    //    capy.checkBox(.{ .label = "Bounded Random" }),
    //});

    const cont_adj = try capy.column(.{ .name = "5" }, .{
        capy.button(.{ .label = "Apply Effect", .onclick = @ptrCast(&buttonClick) }),
        capy.label(.{ .alignment = .Left, .text = "Start Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "End Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "Lower Bound" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "Upper Bound" }),
        capy.textField(.{}),
    });

    const cont_set = try capy.column(.{ .name = "6" }, .{
        capy.button(.{ .label = "Apply Settings", .onclick = @ptrCast(&buttonClick) }),
        capy.label(.{ .alignment = .Left, .text = "osu! Song directory path" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "SV Settings" }),
        capy.checkBox(.{ .label = "Snap SV to notes", .checked = true }),
        capy.checkBox(.{ .label = "Normalize SV over BPM changes", .checked = true }),
        capy.checkBox(.{ .label = "Overwrite ALL previous SV (this includes uninherited points)", .checked = false }),
        // Adjust click handler to this and add these options
        // IDEA: maybe have this save to a settings.zon file?
        //capy.checkBox(.{ .label = "Add SV to all timing points in the effect", .checked = false }),
        //capy.checkBox(.{ .label = "Add SV to all barlines in the effect", .checked = false }), // Will have to get offset of each timing point and then find every barline that would exist in it
        //capy.checkBox(.{ .label = "Points inherit effects from previous points", .checked = false }), // Will have to get offset of each timing point and then find every barline that would exist in it
        capy.label(.{ .alignment = .Left, .text = "File Settings" }),
        capy.checkBox(.{ .label = "Automatically create backup files", .checked = true }),
        //capy.expanded(
        //capy.row(.{}, .{
        capy.label(.{ .alignment = .Left, .text = "Ver 0.0.1 " }),
        //capy.alignment(
        //.{ .x = 1, .y = 1 },
        //capy.image(.{ .url = "https://avatars.githubusercontent.com/u/88110129?v=4", .scaling = .Fit }), // TODO make this A: NOT A FUCKING URL and B: A STATIC SIZE
        //),
        //}),
        //),
    });

    CURR_FILE_LABEL = capy.label(.{ .alignment = .Left, .text = "No file selected..." });

    const tab_lin = capy.tab(.{ .label = "Linear" }, cont_lin);
    const tab_exp = capy.tab(.{ .label = "Exponential" }, cont_exp);
    const tab_sin = capy.tab(.{ .label = "Sine" }, cont_sin);
    //const tab_bez = capy.tab(.{ .label = "Bezier" }, cont_bez);
    const tab_adj = capy.tab(.{ .label = "Adjustments" }, cont_adj);
    const tab_set = capy.tab(.{ .label = "Settings" }, cont_set);

    //const tab_cont = capy.tabs(.{ tab_lin, tab_exp, tab_sin, tab_bez, tab_adj, tab_set });
    const tab_cont = capy.tabs(.{ tab_lin, tab_exp, tab_sin, tab_adj, tab_set });

    //const menu_bar = capy.menu(.{ .label = "menu" }, .{ tab_lin, tab_exp, tab_sin, tab_adj, tab_set }); // FIGURE OUT WHAT THIS DOES
    //const img_CFG = try capy.ImageData.fromFile(std.heap.raw_c_allocator, "../glubby.png");
    //_ = img_CFG;

    //const main_cont = try capy.column(.{ .expand = .Fill }, .{tab_cont});
    //const TEST_IMG = capy.image(.{ .url = "file:///home/koishi/Programming/websites/ieatrocks4fun/images/svbuddy.png", .scaling = .Fit });

    //const REKT = capy.rect(.{ .name = "background-rectangle", .color = capy.Color.blue }), // capy.Color.transparent
    const main_cont = try capy.column(.{ .expand = .No, .spacing = 5 }, .{
        CURR_FILE_LABEL orelse unreachable, // This shouldn't fail
        //TEST_IMG,
        tab_cont,
    });

    window.setPreferredSize(240, 320);

    window.setTitle("SV Buddy");

    try window.set(main_cont);

    window.show();

    capy.runEventLoop();
}
