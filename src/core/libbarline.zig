const std = @import("std");

pub inline fn pxDistToSV(px: u16, target_hres: u16) f32 {
    return target_hres / (px * 460);
}
