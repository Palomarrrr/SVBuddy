// MASSIVE THANKS to gosumemory and cosutrainer!

// NOTES TO SELF: This should be a child process that is spun off on request from the parent program.
//                It should write whatever the current map is to /tmp/svbuddy.pipe
//                Not sure how itll work on windows but... we'll get there when we get there...

// TODO:
//  - Try to spin this off into its own process that communicates via a pipe w/ the main process
//  - OPTIMIZE THIS NIGHTMARE....
//  - uhhh make it just less of a scrapped together mess

const std = @import("std");
const builtin = @import("builtin");

pub const OSU_STATUS_SIG = [_]u8{ 0x48, 0x83, 0xF8, 0x04, 0x73, 0x1E }; // Dont know if this is actually useful
pub const OSU_BASE_SIG = [_]u8{ 0xF8, 0x01, 0x74, 0x04, 0x83, 0x65 };

pub const ProcReadErr = error{
    EndOfMapFile,
    PatternNotFound,
    OsuProcDNE,
};

// TODO: Need to make a seperate Windows proc reader prolly
// You could try to do some comptime fuckery to compress this into one class
pub const UnixProcReader = struct {
    proc_dir: []u8,
    osu_dir: []u8,
    mem_file: std.fs.File,
    map_file: std.fs.File,

    pub fn findOsuProc(self: *UnixProcReader) !void {
        var proc = try std.fs.openDirAbsolute("/proc/", .{ .iterate = true });
        defer proc.close();
        var proc_itr = proc.iterate();
        while (true) {
            const d: std.fs.Dir.Entry = proc_itr.next() catch {
                return ProcReadErr.OsuProcDNE;
            } orelse return ProcReadErr.OsuProcDNE;
            if (d.kind != std.fs.File.Kind.directory) continue;

            const comm_path = try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ @constCast("/proc/"), @constCast(d.name), @constCast("/comm") });
            defer std.heap.page_allocator.free(comm_path);

            const comm_file = std.fs.openFileAbsolute(comm_path, .{}) catch continue;
            defer comm_file.close();

            const contents = try std.heap.page_allocator.alloc(u8, 8);
            defer std.heap.page_allocator.free(contents);
            _ = try comm_file.readAll(contents);

            if (std.ascii.eqlIgnoreCase(contents, "osu!.exe")) { // This seems janky as hell but everywhere points to using this method...
                const proc_path = try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ @constCast("/proc/"), @constCast(d.name) });

                self.proc_dir = try std.heap.page_allocator.alloc(u8, proc_path.len);
                @memcpy(self.proc_dir, proc_path);

                const cmdline_path = try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ @constCast("/proc/"), @constCast(d.name), @constCast("/cmdline") });
                defer std.heap.page_allocator.free(cmdline_path);

                const cmdline_file = try std.fs.openFileAbsolute(cmdline_path, .{});
                defer cmdline_file.close();

                //var cmdline_cont = try std.heap.page_allocator.alloc(u8, try cmdline_file.getEndPos()); // TODO: this could be unsafe but I don't think its too big of a deal?
                // aww shit here we go again... ^ doesnt work... so fml i gotta do this the shitty way
                var cont_len: usize = 0;
                // Try to count up all the lines
                //while (true) {
                //    cmdline_file.seekBy(1) catch break;
                //    cont_len += 1;
                //}
                //try cmdline_file.seekTo(0);

                // NOT EVEN ^ WORKS??????????????????
                // FUCK MEEEEE IM ENDING IT ALL
                const cont_tmp: []u8 = try std.heap.page_allocator.alloc(u8, 256); // If your path is longer than this you have bigger problems to worry about
                defer std.heap.page_allocator.free(cont_tmp);
                cont_len = (try cmdline_file.readAll(cont_tmp));
                cont_len = @divTrunc(cont_len, 2); // I HATE WCHARS!!!!!
                try cmdline_file.seekTo(0); // walk back

                var cmdline_cont = try std.heap.page_allocator.alloc(u8, cont_len);
                defer std.heap.page_allocator.free(cmdline_cont);

                _ = try cmdline_file.readAll(cmdline_cont);

                self.osu_dir = try std.heap.page_allocator.alloc(u8, cmdline_cont.len - 8); // osu!.exe is 8 chars so subtract that from there
                @memcpy(self.osu_dir, cmdline_cont[0 .. cmdline_cont.len - 8]);
                break;
            }
        }
    }

    pub inline fn memReadInit(self: *UnixProcReader) !void {
        self.mem_file = try std.fs.openFileAbsolute(try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ self.proc_dir, @constCast("/mem") }), .{});
    }

    pub inline fn memReadDeinit(self: *UnixProcReader) void {
        self.mem_file.close();
    }

    pub fn memRead(self: *UnixProcReader, base: usize, buffer: *[]u8) !void {
        try self.mem_file.seekTo(base);
        _ = try self.mem_file.readAll(buffer.*);
    }

    pub inline fn mapReadInit(self: *UnixProcReader) !void {
        self.map_file = try std.fs.openFileAbsolute(try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ self.proc_dir, @constCast("/maps") }), .{});
    }

    pub inline fn mapReadDeinit(self: *UnixProcReader) void {
        self.map_file.close();
    }

    pub fn getNextMapReg(self: *UnixProcReader) ![2]u32 { // Returns []u32{start, len}
        var line = [_]u8{0} ** 512;
        var exts = [_]u32{ 0, 0 };
        var idx = [_]u32{ 0, 0 }; // location of '-', location of ' '

        outer: while (true) {
            @memset(&line, 0); // rst this
            // Check if we can read this memory
            const b = self.map_file.readAll(&line) catch |er| {
                return er;
            };

            if (b <= 0) {
                return ProcReadErr.EndOfMapFile;
            }

            var i: usize = 0;
            var j: usize = 0;
            var e: usize = 0;

            // Find special chars
            // while i < 2
            inner: while (true) : (j += 1) {
                switch (line[j]) {
                    '-', ' ' => {
                        if (i < 2) {
                            idx[i] = @intCast(j);
                            i += 1;
                        }
                    },
                    '\n', '\r', 0 => {
                        e = j;
                        break :inner;
                    },
                    else => continue :inner,
                }
            }

            // Walk back the dist past the first \n or \r
            try self.map_file.seekBy(0 - @as(i64, @intCast(b - e - 1)));

            if (line[idx[1] + 1] == '0' or line[idx[1] + 1] == 0) return ProcReadErr.EndOfMapFile;
            if (line[idx[1] + 1] == 'r') break :outer;
        }

        // Package the data up
        exts[0] = try std.fmt.parseInt(u32, line[0..idx[0]], 16);
        exts[1] = (try std.fmt.parseInt(u32, line[idx[0] + 1 .. idx[1]], 16)) - exts[0];

        return exts;
    }

    pub fn memFindPat(self: *UnixProcReader, needle: []u8) !u32 { // Removed masks because i don't think im going to use it

        // This causes errors and has to be done manually now
        //try self.mapReadInit();
        //defer self.mapReadDeinit();

        while (true) {
            const reg = self.getNextMapReg() catch break;
            if (reg[1] < needle.len) continue;

            // IMPORTANT TODO:
            // OK THIS ALLOCS WAY TOO FUCKING MUCH MEMORY!!!!!!!!!!!!!
            //      (AT THE TIME OF WRITING... 9MB IN ONE FUCKING GO???????????????)
            //
            // TRY TO MAKE IT NOT DO THAT????

            var haystack = try std.heap.page_allocator.alloc(u8, reg[1]);
            defer std.heap.page_allocator.free(haystack);

            try self.memReadInit();
            defer self.memReadDeinit();

            try self.memRead(reg[0], &haystack);

            if (std.ascii.indexOfIgnoreCase(haystack, needle)) |offset| {
                return @intCast(reg[0] + offset);
            } else {
                continue;
            }
        }
        return ProcReadErr.PatternNotFound;
    }

    fn getBeatmapPtr(self: *UnixProcReader, base: usize) !u32 {
        var new_base: u32 = 0;
        //var buf = [_]u8{ 0, 0, 0, 0 }; // I AM GOING TO KILL MY SELF
        var buf = try std.heap.page_allocator.alloc(u8, 4);
        defer std.heap.page_allocator.free(buf);

        try self.memReadInit();
        defer self.memReadDeinit();

        try self.memRead(base - 0x0C, &buf);
        new_base = castToU32(&buf);
        try self.memRead(new_base, &buf);
        return castToU32(&buf);
    }

    pub fn getBeatmapPath(self: *UnixProcReader, base: usize) ![]u8 {
        const bm_ptr = try self.getBeatmapPtr(base);
        std.debug.print("LOG: Loaded beatmap ptr: {}\n", .{bm_ptr});
        //var buf = [_]u8{ 0, 0, 0, 0 };
        var buf = try std.heap.page_allocator.alloc(u8, 4); // IM KILLING MYSELFFFFFFF
        defer std.heap.page_allocator.free(buf);

        // Set up memreader
        try self.memReadInit();
        defer self.memReadDeinit();

        try self.memRead(bm_ptr + 0x78, &buf); // TODO: what are these offsets?
        const dir_ptr = castToU32(&buf);
        try self.memRead(dir_ptr + 0x04, &buf);
        const dir_sz = castToU32(&buf);

        try self.memRead(bm_ptr + 0x90, &buf);
        const path_ptr = castToU32(&buf);
        try self.memRead(path_ptr + 0x04, &buf);
        const path_sz = castToU32(&buf);

        var dir_str: []u8 = try std.heap.page_allocator.alloc(u8, dir_sz * 2);
        var path_str: []u8 = try std.heap.page_allocator.alloc(u8, path_sz * 2);

        try self.memRead(dir_ptr + 8, &dir_str);
        try self.memRead(path_ptr + 8, &path_str);

        return try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ dir_str, @constCast("/"), path_str });
    }

    pub fn deinit(self: *UnixProcReader) void {
        //self.memReadDeinit();
        //self.mapReadDeinit();
        std.heap.page_allocator.free(self.osu_dir);
        std.heap.page_allocator.free(self.proc_dir);
    }

    pub fn toStr(self: *UnixProcReader) ![]u8 { // Just a test fn
        var base: usize = 0;
        std.debug.print("LOG: Attempting to find proc dir...\n", .{});
        try self.findOsuProc(); // find the process
        std.debug.print("LOG: Found osu proc dir: {s}\n", .{self.*.proc_dir});
        std.debug.print("LOG: Found osu real dir: {s}\n", .{self.*.osu_dir});
        std.debug.print("LOG: Attempting to scan mem...\n", .{});
        try self.mapReadInit(); // This needs to be done manually rn
        if (base == 0) {
            base = try self.*.memFindPat(@constCast(&OSU_BASE_SIG));
        }
        std.debug.print("LOG: Found base addr: {}\n", .{base});
        var map_path: []u8 = undefined; // FUCK YOUUU
        map_path = try self.getBeatmapPath(base);
        defer std.heap.page_allocator.free(map_path); // ERR?

        std.debug.print("Got beatmap path of: {s}Songs/{s}\n", .{ self.osu_dir, map_path });

        const ret = try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ self.osu_dir, @constCast("Songs/"), map_path });
        defer self.mapReadDeinit();
        return ret;
    }
};

// Small local helper fn to cast a 4 byte array to a single u32 | I think I could probably accomplish the same thing with `@bitCast()` ?
inline fn castToU32(in: *[]u8) u32 {
    var out: u32 = 0;
    out = in.*[3];
    out <<= 8;
    out |= (in.*[2]);
    out <<= 8;
    out |= (in.*[1]);
    out <<= 8;
    out |= (in.*[0]);
    @memset(in.*, 0);
    return out;
}
