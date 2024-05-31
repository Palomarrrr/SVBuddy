// Big thanks to gosumemory and cosutrainer - TODO: ADD CREDITS

// NOTES TO SELF: This should be a child process that is spun off on request from the parent program.
//                It should write whatever the current map is to /tmp/svbuddy.pipe
//                Not sure how itll work on windows but... we'll get there when we get there...

// TODO:
//      - Need to write main fn to set up the ProcReader w/ the proc dir etc
//        as well as get the proper base address
//              * Check cosutrainer/src/cosumem.c - int main() for guidence
//                  ^ https://github.com/hwsmm/cosutrainer/blob/master/src/cosumem.c
//
//      - TEST IF ANY OF THIS FUCKING WORKS :(((((((((((((

const std = @import("std");
const builtin = @import("builtin");

pub const OSU_STATUS_SIG = [_]u8{ 0x48, 0x83, 0xF8, 0x04, 0x73, 0x1E };
pub const OSU_BASE_SIG = [_]u8{ 0xF8, 0x01, 0x74, 0x04, 0x83, 0x65 };

// Maybe just aggregate this into a main fn
pub const ProcInfo = struct {
    //song_folder: []u8, // Not sure if I'll really use this
    //parent_dir: []u8, // Same as above
    file_path: []u8,
    bg_file_name: []u8,
    p_reader: *UnixProcReader,

    pub fn init(self: *ProcInfo) !void {
        try self.p_reader.findOsuProc(); // I think thats it?
    }

    pub fn getCurMap(self: *ProcInfo) !void {
        _ = self;
    }

    pub fn deinit(self: *ProcInfo) void {
        std.heap.page_allocator.free(self.file_path);
        std.heap.page_allocator.free(self.bg_file_name);
        self.p_reader.*.deinit();
    }
};

// Look at gosumemory/memory/init.go
// TODO: Need to make a seperate Windows proc reader prolly
// You could try to do some comptime fuckery to compress this into one class
pub const UnixProcReader = struct {
    proc_dir: []u8,
    osu_dir: []u8,
    mem_file: std.fs.File,
    map_file: std.fs.File,

    pub fn findOsuProc(self: *UnixProcReader) !void {
        const proc = try std.fs.openDirAbsolute("/proc/", .{ .iterate = true });
        defer proc.close();
        var proc_itr = proc.iterate();
        while (true) {
            const d: std.fs.Dir = proc_itr.next() catch {
                break;
            } orelse break;
            if (d.kind != std.fs.File.Kind.directory) continue;

            const comm_path = try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ @constCast("/proc/"), @constCast(d.basename), @constCast("/comm") });
            defer std.heap.page_allocator.free(comm_path);

            const comm_file = try std.fs.openFileAbsolute(comm_path, .{}) catch {
                std.debug.print("LOG: \x1b[31mFAILED TO OPEN `{s}`\x1b[0m\n", .{comm_path});
                continue;
            };
            defer comm_file.close();

            const contents = try std.heap.page_allocator.alloc(u8, 8);
            defer std.heap.page_allocator.free(contents);
            try comm_file.readAll(contents);

            if (std.ascii.eqlIgnoreCase(contents, "osu!.exe")) { // This seems janky as hell but everywhere points to using this method...
                const proc_path = try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ @constCast("/proc/"), @constCast(d.basename) });

                self.proc_dir = try std.heap.page_allocator.alloc(u8, proc_path.len);
                @memcpy(self.proc_dir, proc_path);

                const cmdline_path = try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ @constCast("/proc/"), @constCast(d.basename), @constCast("/cmdline") });
                defer std.heap.page_allocator.free(cmdline_path);

                const cmdline_file = try std.fs.openFileAbsolute(cmdline_path, .{});
                defer cmdline_file.close();

                var cmdline_cont = try std.heap.page_allocator.alloc(u8, try cmdline_file.getEndPos()); // TODO: this could be unsafe but I don't think its too big of a deal?
                defer std.heap.page_allocator.free(cmdline_cont);

                try cmdline_file.readAll(cmdline_cont);

                self.osu_dir = try std.heap.page_allocator.alloc(u8, cmdline_cont.len - 8); // osu!.exe is 8 chars so subtract that from there
                @memcpy(self.osu_dir, cmdline_cont[0 .. cmdline_cont.len - 7]); // MAYERR
                break;
            }
        }
    }

    pub inline fn memReadInit(self: *UnixProcReader) !void {
        self.mem_file = try std.fs.openFileAbsolute(try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ self.proc_dir, @constCast("mem") }), .{});
    }

    pub inline fn memReadDeinit(self: *UnixProcReader) void {
        self.mem_file.close();
    }

    pub fn memRead(self: *UnixProcReader, base: usize, buffer: *[]u8) !void {
        try self.mem_file.seekTo(base);
        try self.mem_file.readAll(buffer.*);
    }

    pub inline fn mapReadInit(self: *UnixProcReader) !void {
        self.map_file = try std.fs.openFileAbsolute(try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ self.proc_dir, @constCast("maps") }), .{});
    }

    pub inline fn mapReadDeinit(self: *UnixProcReader) void {
        self.map_file.close();
    }

    pub fn getNextMapReg(self: *UnixProcReader) ![2]u32 { // Returns []u32{start, len}
        var line = [_]u8{0} ** 1024;
        var exts = [_]u32{ 0, 0 };

        self.map_file.readAll(&line);

        var idx = [_]u32{ 0, 0 }; // location of '-', location of ' '
        var i: usize = 0;
        var j: usize = 0;

        // Find special chars
        while (i < 2) : (j += 1) {
            switch (line[j]) {
                '-', ' ' => {
                    idx[i] = j;
                    i += 1;
                },
                else => continue,
            }
        }

        // Check if we can read this memory
        std.debug.print("DEBUG: line[idx[1] + 1] == {c}\n", .{line[idx[1] + 1]}); //DBG
        if (line[idx[1] + 1] != 'r') return self.getNextMapReg(); // TODO: make non recursive s.t. we don't eat up stack space

        // Package the data up
        exts[0] = try std.fmt.parseInt(u32, line[0..idx[0]], 16);
        exts[1] = (try std.fmt.parseInt(u32, line[idx[0] + 1 .. idx[1]], 16)) - exts[0];

        return exts;
    }

    pub fn memFindPat(self: *UnixProcReader, pat: []u8) !u32 { // Removed masks because i don't think im going to use it
        try self.mapReadInit();
        defer self.mapReadDeinit();

        while (true) {
            const reg = self.getNextMapReg() catch {
                break;
            };

            if (reg[1] < pat.len) continue;

            var buffer = try std.heap.page_allocator.alloc(u8, reg[1]);
            defer std.heap.page_allocator.free(buffer);

            try self.memRead(reg[0], &buffer);

            if (std.ascii.indexOfIgnoreCase(buffer, pat)) |offset| {
                return reg[0] + offset;
            } else continue;
        }
    }

    fn getBeatmapPtr(self: *UnixProcReader, base: usize) !u32 {
        var new_base: u32 = 0;
        var buf = [_]u8{ 0, 0, 0, 0 };

        try self.memReadInit();
        defer self.memReadDeinit();

        try self.memRead(base - 0x0C, &buf);
        new_base = castToU32(&buf);
        try self.memRead(new_base, &buf);

        return castToU32(&buf);
    }

    pub fn getBeatmapPath(self: *UnixProcReader, base: usize) ![]u8 {
        const bm_ptr = try self.getBeatmapPtr(base);
        var buf = [_]u8{ 0, 0, 0, 0 };

        self.memRead(bm_ptr + 0x78, &buf); // TODO: what are these offsets?
        const dir_ptr = castToU32(&buf);
        self.memRead(dir_ptr + 0x04, &buf);
        const dir_sz = castToU32(&buf);

        self.memRead(bm_ptr + 0x90, &buf);
        const path_ptr = castToU32(&buf);
        self.memRead(path_ptr + 0x04, &buf);
        const path_sz = castToU32(&buf);

        // I HATE WCHARS AAAAAAAAAAAAAAAAAAAAAAAAAA
        // These are basically u16 arrs but disguised as u8s for ease of use
        // MAYERR: I think this is ok
        var dir_str: []u8 = try std.heap.page_allocator.alloc(u8, dir_sz * 2);
        var path_str: []u8 = try std.heap.page_allocator.alloc(u8, path_sz * 2);

        self.memRead(dir_ptr + 8, &dir_str);
        self.memRead(path_ptr + 8, &path_str);

        return try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ dir_str, @constCast("/"), path_str });
    }

    pub fn deinit(self: *UnixProcReader) void {
        self.memReadDeinit();
        self.mapReadDeinit();
        std.heap.page_allocator.free(self.osu_dir);
        std.heap.page_allocator.free(self.proc_dir);
    }
};

// Small local helper fn to cast a 4 byte array to a single u32 | I think I could probably accomplish the same thing with `@bitCast()` ?
inline fn castToU32(in: *[4]u8) u32 {
    var out: u32 = 0;
    out = in.*[0];
    out |= (in.*[1] << 8);
    out |= (in.*[2] << 16);
    out |= (in.*[3] << 24);
    @memset(in.*, 0);
    return out;
}
