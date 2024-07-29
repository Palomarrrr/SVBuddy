pub const packages = struct {
    pub const @"1220c94dbcdf5a799ce2b1571978ff3c97bab1341fe329084fcc3c06e5d6375469b9" = struct {
        pub const available = false;
    };
    pub const @"1220d397a6dfd4389b6bf9ecdd6be1421a919ae02adb4f658a6ccb2dac84804db07c" = struct {
        pub const available = false;
    };
    pub const @"1220dc313944ea71a87b4f54f26b1427ad2992a721a221cb42f7f80b8eee4e4944b7" = struct {
        pub const build_root = "/home/koishi/.cache/zig/p/1220dc313944ea71a87b4f54f26b1427ad2992a721a221cb42f7f80b8eee4e4944b7";
        pub const build_zig = @import("1220dc313944ea71a87b4f54f26b1427ad2992a721a221cb42f7f80b8eee4e4944b7");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"1220ec02166a05940167f5f2cad27be15a5061fd23da2fd1b2efc481c6689a753dce" = struct {
        pub const build_root = "/home/koishi/.cache/zig/p/1220ec02166a05940167f5f2cad27be15a5061fd23da2fd1b2efc481c6689a753dce";
        pub const build_zig = @import("1220ec02166a05940167f5f2cad27be15a5061fd23da2fd1b2efc481c6689a753dce");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "zig-objc", "1220c94dbcdf5a799ce2b1571978ff3c97bab1341fe329084fcc3c06e5d6375469b9" },
            .{ "macos_sdk", "1220d397a6dfd4389b6bf9ecdd6be1421a919ae02adb4f658a6ccb2dac84804db07c" },
            .{ "zigimg", "1220dc313944ea71a87b4f54f26b1427ad2992a721a221cb42f7f80b8eee4e4944b7" },
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "capy", "1220ec02166a05940167f5f2cad27be15a5061fd23da2fd1b2efc481c6689a753dce" },
};
