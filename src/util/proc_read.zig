// Big thanks to gosumemory - TODO: ADD CREDITS

const std = @import("std");
const builtin = @import("builtin");

const ProcInfo = struct {
    //song_folder: []u8, // Not sure if I'll really use this
    //parent_dir: []u8, // Same as above
    file_path: []u8,
    bg_file_name: []u8,

    pub fn init(self: *ProcInfo, path: []u8, bg_name: []u8) !void {
        self.file_path = try std.heap.page_allocator.alloc(u8, path.len); // Alloc space
        @memcpy(self.file_path, path);
        self.bg_file_name = try std.heap.page_allocator.alloc(u8, bg_name.len);
        @memcpy(self.bg_file_name, bg_name);
        // TODO: Cut off parent dir and store if needed
    }

    pub fn deinit(self: *ProcInfo) void {
        std.heap.page_allocator.free(self.file_path);
        std.heap.page_allocator.free(self.bg_file_name);
    }
};

// Look at gosumemory/memory/init.go
// I think youd have to use at least popen/pread for linux and fuck idk about how to go about it w/ windows
//const ProcReader = struct {
//
//};
