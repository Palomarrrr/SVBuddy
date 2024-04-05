const std = @import("std");
const capy = @import("capy");
const sv = @import("./core/libsv.zig");
const osufile = @import("./core/osufileio.zig");
const hitobj = @import("./core/hitobj.zig");
const com = @import("./util/common.zig");

// This is required for your app to build to WebAssembly and other particular architectures
pub usingnamespace capy.cross_platform;

// TODO - MAKE THIS DYNAMIC | find a way to get some kind of "name" field from the parent and then switch off that
fn buttonClick(btn: *capy.Button) anyerror!void {
    const parent_wgt = btn.*.getParent().?.as(capy.Container);
    //const text_wgt = try parent_wgt.*.getChildAt(2).as(capy.TextField);
    const parent_name = parent_wgt.widget.?.name.get() orelse unreachable;

    var i: usize = 2;
    var p: usize = 0;
    var max: usize = 0;

    var params = try std.heap.raw_c_allocator.alloc([]u8, 6);

    switch (parent_name[0] - '0') {
        1, 2, 5 => max = 8,
        3 => max = 10,
        4 => max = 12,
        6 => max = 2,
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
        // Wrapper fns go here
        else => unreachable,
    }

    btn.setLabel("Applied");
}

pub fn main() !void {
    try capy.backend.init();

    var window = try capy.Window.init();
    defer window.deinit();

    const target_fp: ?[]u8 = null;
    _ = target_fp;

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
        capy.label(.{ .alignment = .Left, .text = "osu! song file path" }),
        capy.textField(.{}),
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

    var osu_file: osufile.OsuFile = undefined;
    try osu_file.init("/home/koishi/Programming/Zig/svbuddy/osu_testfiles/quarks.osu");

    std.debug.print("\n\nSECTION OFFSETS\n", .{});
    for (osu_file.section_offsets) |s| std.debug.print("{}\n", .{s});

    const bet = osu_file.extentsOfSection(787, 4000, hitobj.HitObject);
    std.debug.print("\nFOUND POINT AT: {any}\n", .{bet});
    const bet2 = osu_file.extentsOfSection(787, 4000, sv.TimingPoint);
    std.debug.print("\nFOUND POINT AT: {any}\n", .{bet2});

    try osu_file.reset();

    osu_file.deinit();
    try window.set(main_cont);

    window.show();

    capy.runEventLoop();
}
