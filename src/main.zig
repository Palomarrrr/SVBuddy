const std = @import("std");
const capy = @import("capy");
const osufile = @import("./core/osufileio.zig");
const com = @import("./util/common.zig");
const backend = @import("./util/backend_wrappers.zig");

// This is required for your app to build to WebAssembly and other particular architectures
pub usingnamespace capy.cross_platform;

// This is awful but its the only way i can think of passing this
var CURR_FILE: ?*osufile.OsuFile = null;

// TODO - MAKE THIS DYNAMIC | find a way to get some kind of "name" field from the parent and then switch off that
fn buttonClick(btn: *capy.Button) anyerror!void {
    const parent_wgt = btn.*.getParent().?.as(capy.Container);
    const parent_name = parent_wgt.widget.?.name.get() orelse unreachable;

    var i: usize = 2;
    var p: usize = 0;
    var max: usize = 0;
    var option_bflag: u8 = 0;

    var params = try std.heap.raw_c_allocator.alloc([]u8, 6);

    switch (parent_name[0] - '0') {
        1, 2, 5 => max = 8,
        3 => max = 10,
        4 => max = 12,
        6 => { // 4,5,6,8
            max = 2;

            // Get the status of all options in the settings menu
            const check_wg = (try parent_wgt.*.getChildAt(4)).as(capy.CheckBox); // 4
            const check = check_wg.*.checked.get();
            const check_wg2 = (try parent_wgt.*.getChildAt(5)).as(capy.CheckBox);
            const check2 = check_wg2.*.checked.get();
            const check_wg3 = (try parent_wgt.*.getChildAt(6)).as(capy.CheckBox);
            const check3 = check_wg3.*.checked.get();
            const check_wg4 = (try parent_wgt.*.getChildAt(8)).as(capy.CheckBox);
            const check4 = check_wg4.*.checked.get();

            // TODO: FUCK YOU FOR DOING THIS
            if (check) option_bflag |= 0x1;
            if (check2) option_bflag |= 0x2;
            if (check3) option_bflag |= 0x4;
            if (check4) option_bflag |= 0x8;
        },
        else => unreachable,
    }

    while (i <= max) : (i += 2) {
        const text_wgt = (try parent_wgt.*.getChildAt(i)).as(capy.TextField);
        const text_out = text_wgt.*.text.get();
        params[p] = try std.heap.raw_c_allocator.alloc(u8, text_out.len);
        @memcpy(params[p], text_out);
        p += 1;
    }

    switch (parent_name[0] - '0') {
        1 => try backend.linear(CURR_FILE, params),
        2 => try backend.exponential(CURR_FILE, params),
        //3 => try backend.sinusoidal(CURR_FILE, params),
        //4 => try backend.bezier(CURR_FILE, params),
        //5 => try backend.adjust(CURR_FILE, params),
        6 => {
            params[1] = try std.heap.raw_c_allocator.alloc(u8, 1);
            params[1][0] = option_bflag;
            CURR_FILE = try backend.initTargetFile(params);
        },
        else => unreachable,
    }

    btn.setLabel("Applied");
}

pub fn main() !void {
    try capy.backend.init();

    var window = try capy.Window.init();
    defer window.deinit();

    const target_path: ?[]u8 = null;
    _ = target_path;

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
        capy.checkBox(.{ .label = "Bounded Random" }),
        capy.label(.{ .alignment = .Left, .text = "Variance" }),
        capy.textField(.{ .readOnly = true }),
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
        capy.checkBox(.{ .label = "Bounded Random" }),
    });

    const cont_sin = try capy.column(.{ .name = "3" }, .{
        capy.button(.{ .label = "Apply Effect", .onclick = @ptrCast(&buttonClick) }),
        capy.label(.{ .alignment = .Left, .text = "Start Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "End Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "Amplitude" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "Period" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "Frequency" }),
        capy.textField(.{}),
        capy.checkBox(.{ .label = "Bounded Random" }),
    });

    const cont_bez = try capy.column(.{ .name = "4" }, .{
        capy.button(.{ .label = "Apply Effect", .onclick = @ptrCast(&buttonClick) }),
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
        capy.checkBox(.{ .label = "Bounded Random" }),
    });

    const cont_adj = try capy.column(.{ .name = "5" }, .{
        capy.button(.{ .label = "Apply Effect", .onclick = @ptrCast(&buttonClick) }),
        capy.label(.{ .alignment = .Left, .text = "Start Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "End Time" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "Upper Bound" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "Lower Bound" }),
        capy.textField(.{}),
    });

    const cont_set = try capy.column(.{ .name = "6" }, .{
        capy.button(.{ .label = "Apply Settings", .onclick = @ptrCast(&buttonClick) }),
        capy.label(.{ .alignment = .Left, .text = "osu! Song directory path" }),
        capy.textField(.{}),
        capy.label(.{ .alignment = .Left, .text = "SV Settings" }),
        capy.checkBox(.{ .label = "Snap SV to notes", .checked = true }),
        capy.checkBox(.{ .label = "Normalize SV over BPM changes", .checked = true }),
        capy.checkBox(.{ .label = "Overwrite all previous SV", .checked = false }),
        capy.label(.{ .alignment = .Left, .text = "File Settings" }),
        capy.checkBox(.{ .label = "Automatically create backup files", .checked = true }),
        capy.label(.{ .alignment = .Left, .text = "Ver 0.0.1 ALPHA" }),
    });

    const tab_lin = capy.tab(.{ .label = "Linear" }, cont_lin);
    const tab_exp = capy.tab(.{ .label = "Exponential" }, cont_exp);
    const tab_sin = capy.tab(.{ .label = "Sine" }, cont_sin);
    const tab_bez = capy.tab(.{ .label = "Bezier" }, cont_bez);
    const tab_adj = capy.tab(.{ .label = "Adjustments" }, cont_adj);
    const tab_set = capy.tab(.{ .label = "Settings" }, cont_set);

    const tab_cont = capy.tabs(.{ tab_lin, tab_exp, tab_sin, tab_bez, tab_adj, tab_set });

    // TODO - Look into how the graph example works
    var sv_graph = capy.canvas(.{});
    // TODO - Figure out how to make a drawContext
    //sv_graph.ref();
    //defer sv_graph.unref();
    sv_graph = sv_graph.setPreferredSize(.{ .width = 320, .height = 240 });
    // Test Rectangle

    const main_cont = try capy.column(.{ .expand = .Fill }, .{ sv_graph, tab_cont });

    window.setTitle("SV Buddy");

    try window.set(main_cont);

    window.show();

    capy.runEventLoop();
}
