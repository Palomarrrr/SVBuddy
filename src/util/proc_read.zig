// MASSIVE THANKS TO gosumemory AND cosutrainer FOR EXAMPLES ON READING OSU PROCESS DATA!!!

// NOTES TO SELF: This should be a child process that is spun off on request from the parent program.
//                It should write whatever the current map is to /tmp/svbuddy.pipe
//                Not sure how itll work on windows but... we'll get there when we get there...

// TODO:
//  - Try to spin this off into its own process that communicates via a pipe w/ the main process
//  - OPTIMIZE THIS NIGHTMARE....
//  - uhhh make it just less of a scrapped together mess

//  KNOWN BUGS:
//  - CURRENTLY CRASHES IF I TRY TO LOOK AT MY (5_5) MAP OF `lovely freezing tomboy bath - (-273.15`C)`, hivie's `<<nttld:.beings>>`, and some other maps...
//      * nttld - I think this is a problem with there being a `:` in the title and the metadata parsing getting confused
//      * Tomboy Bath - Something about an integer overflow when doing shit w/ metadata | Might be the same kind of utf8 issue as previous

const std = @import("std");
const builtin = @import("builtin");
const REG_T = std.os.windows.REG;
const win = std.os.windows;

pub const OSU_STATUS_SIG = [_]u8{ 0x48, 0x83, 0xF8, 0x04, 0x73, 0x1E }; // This isn't really used and i dont think its that useful actually
pub const OSU_BASE_SIG = [_]u8{ 0xF8, 0x01, 0x74, 0x04, 0x83, 0x65 };

pub const ProcReadErr = error{
    EndOfMapFile,
    PatternNotFound,
    OsuProcDNE,
    OsuFailedToReadReg,
    FailedToConvertU8ToU16,
};

pub const ProcReader = switch (builtin.os.tag) {
    .linux => struct {
        // TODO: Make this switch between linux and windows proc readers during comptime
        proc_dir: []u8,
        osu_dir: []u8,
        mem_file: std.fs.File,
        map_file: std.fs.File,
        beatmap_base: u32 = 0,

        pub fn findOsuProc(self: *ProcReader) !void {
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

                    //var cmdline_cont = try std.heap.page_allocator.alloc(u8, try cmdline_file.getEndPos()); // FIXME: Possibly unsafe?
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

                    // OK SO PROBLEM THIS ONLY WORKS WHEN NO CMD FLAGS ARE USED
                    //self.osu_dir = try std.heap.page_allocator.alloc(u8, cmdline_cont.len - 8); // osu!.exe is 8 chars so subtract that from there
                    //@memcpy(self.osu_dir, cmdline_cont[0 .. cmdline_cont.len - 8]);

                    // That should work better
                    var dirlen: usize = 0;
                    for (cmdline_cont, 0..) |c, i| { // Find the last '/'
                        if (c == '/') dirlen = i + 1;
                    }
                    self.osu_dir = try std.heap.page_allocator.alloc(u8, dirlen);
                    @memcpy(self.osu_dir, cmdline_cont[0..dirlen]);

                    break;
                }
            }
        }

        pub fn deinit(self: *ProcReader) void {
            //self.memReadDeinit();
            //self.mapReadDeinit();
            std.heap.page_allocator.free(self.osu_dir);
            std.heap.page_allocator.free(self.proc_dir);
        }

        pub inline fn memReadInit(self: *ProcReader) !void {
            self.mem_file = try std.fs.openFileAbsolute(try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ self.proc_dir, @constCast("/mem") }), .{});
        }

        pub inline fn memReadDeinit(self: *ProcReader) void {
            self.mem_file.close();
        }

        pub fn memRead(self: *ProcReader, base: usize, buffer: *[]u8) !void {
            try self.mem_file.seekTo(base);
            _ = try self.mem_file.readAll(buffer.*);
        }

        pub inline fn mapReadInit(self: *ProcReader) !void {
            self.map_file = try std.fs.openFileAbsolute(try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ self.proc_dir, @constCast("/maps") }), .{});
        }

        pub inline fn mapReadDeinit(self: *ProcReader) void {
            self.map_file.close();
        }

        pub fn getNextMapReg(self: *ProcReader) ![2]u32 { // Returns []u32{start, len}
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

        pub fn memFindPat(self: *ProcReader, needle: []u8) !u32 { // Removed masks because i don't think im going to use it

            // This causes errors and has to be done manually now
            //try self.mapReadInit();
            //defer self.mapReadDeinit();

            while (true) {
                const reg = self.getNextMapReg() catch break;
                if (reg[1] < needle.len) continue;

                // IMPORTANT TODO:
                // OK THIS ALLOCS WAY TOO FUCKING MUCH MEMORY!!!!!!!!!!!!!
                //      (AT THE TIME OF WRITING... IT ALLOCED 9MB IN ONE FUCKING GO???????????????)
                //
                // TRY TO MAKE IT NOT DO THAT YEAH????

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

        fn getBeatmapPtr(self: *ProcReader, base: usize) !u32 {
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

        pub fn getBeatmapPath(self: *ProcReader, base: usize) ![]u8 {
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

            // Convert these to utf8 because theyre currently in utf16 for some reason...
            const dir_u16str = try u8ArrToU16Arr(&dir_str);
            const dir_utf8str = try std.unicode.utf16leToUtf8Alloc(std.heap.page_allocator, dir_u16str);
            const path_u16str = try u8ArrToU16Arr(&path_str);
            const path_utf8str = try std.unicode.utf16leToUtf8Alloc(std.heap.page_allocator, path_u16str);

            return try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ dir_utf8str, @constCast("/"), path_utf8str });
        }

        pub fn toStr(self: *ProcReader) ![]u8 { // Just a test fn
            if (self.*.beatmap_base == 0) { // Not needed if we already have the base |
                std.debug.print("LOG: FIRST RUN | Attempting to find proc dir...\n", .{});
                try self.findOsuProc(); // Find the process
                std.debug.print("LOG: Found osu proc dir: {s}\n", .{self.*.proc_dir});
                std.debug.print("LOG: Found osu real dir: {s}\n", .{self.*.osu_dir});
            } else std.debug.print("LOG: RAN PREVIOUSLY: Proc dir and real dir already found\n", .{});
            std.debug.print("LOG: Attempting to scan mem...\n", .{});

            // This needs to be done manually rn
            try self.mapReadInit();
            defer self.mapReadDeinit();

            // This speeds things up greatly
            if (self.*.beatmap_base == 0) {
                self.*.beatmap_base = try self.*.memFindPat(@constCast(&OSU_BASE_SIG)); // Find beatmap base
                std.debug.print("LOG: Found base addr: {}\n", .{self.*.beatmap_base});
            }

            const map_path = try self.getBeatmapPath(self.*.beatmap_base);
            defer std.heap.page_allocator.free(map_path);

            std.debug.print("Got beatmap path of: {s}Songs/{s}\n", .{ self.osu_dir, map_path });

            const ret = try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ self.osu_dir, @constCast("Songs/"), map_path });
            return ret;
        }
    },
    .windows => struct {
        // This shit is basically a fuckin port from cosutrainer... I have zero clue how windows works and this makes me want to super die
        osu_dir: win.LPWSTR,
        mem_file: std.fs.File,
        map_file: std.fs.File,

        // Zig doesn't have this in os.windows but this should do the same thing
        inline fn StrRChrW(haystack: []win.WCHAR, needle: win.WCHAR) ?usize {
            var idx: usize = haystack.len + 1;
            for (haystack, 0..) |wc, i| {
                if (wc == needle) idx = i;
            }
            return if (idx == haystack.len + 1) null else idx;
        }

        inline fn StrChrW(haystack: []win.WCHAR, needle: win.WCHAR) ?usize {
            for (haystack, 0..) |wc, i| {
                if (wc == needle) return i;
            }
            return null;
        }

        // Small intermediate fn
        inline fn wStrEq(a: []win.WCHAR, b: []win.WCHAR) bool {
            if (a.len != b.len) return false;
            for (a, b) |ca, cb| {
                if (ca != cb) return false;
            }
            return true;
        }

        // Given two strings, find the needle in the haystack and return the starting index of the needle
        // This is innefficient as fuck but I just want to get this working god damnit
        inline fn StrStrIW(haystack: []win.WCHAR, needle: []win.WCHAR) ?usize {
            if ((haystack.len -% needle.len) > haystack.len) return null; // Only true if overflow occured
            for (0..(haystack.len - needle.len) + 1) |i| {
                if (wStrEq(haystack[i .. needle.len + i], needle)) return i;
            }
            return null;
        }

        pub fn deinit(self: *ProcReader) void {
            _ = self;
            //
        }

        pub fn findOsuProc(self: *ProcReader) !void {
            var size: win.DWORD = 0;
            // I dont know if these auto cast???
            const lp_sub_key = [_:0]win.WCHAR{ 'o', 's', 'u', '\\', 's', 'h', 'e', 'l', 'l', '\\', 'o', 'p', 'e', 'n', '\\', 'c', 'o', 'm', 'm', 'a', 'n', 'd' }; // Im killing myself
            const empty = [_:0]win.WCHAR{0};
            var ret: win.LSTATUS = win.advapi32.RegGetValueW(win.HKEY_CLASSES_ROOT, &lp_sub_key, &empty, win.advapi32.RRF.RT_REG_SZ, null, null, &size);
            if (ret != 0) {
                return ProcReadErr.OsuProcDNE;
            }
            var path = try std.heap.page_allocator.alloc(win.WCHAR, size);
            ret = win.advapi32.RegGetValueW(win.HKEY_CLASSES_ROOT, &lp_sub_key, &empty, win.advapi32.RRF.RT_REG_SZ, null, @ptrCast(&path), &size);
            if (ret != 0) {
                return ProcReadErr.OsuFailedToReadReg;
            }
            std.debug.print("REG_PATH: {any}\n", .{path});

            // Probably doesn't work... and leaks memory if it does...
            var end_idx: usize = (StrRChrW(path, ' ') orelse path.len) + 1;
            if (end_idx != path.len + 1) path = path[0..end_idx];

            end_idx = (StrRChrW(path, '"') orelse path.len) + 1;
            if (end_idx != path.len + 1) path = path[0..end_idx];

            const start_idx: usize = (StrChrW(path, '"') orelse 0) + 1;

            const osuexe = [_]win.WCHAR{ 'o', 's', 'u', '!', '.', 'e', 'x', 'e' }; // I HATE THIS
            end_idx = (StrStrIW(path, @constCast(&osuexe)) orelse path.len) + 1;
            if (end_idx == path.len) {
                //std.heap.page_allocator.free(path); // Probably errs
                return ProcReadErr.OsuFailedToReadReg;
            }

            path = path[0..end_idx];

            path = path[start_idx..path.len]; // Hopefully this works?

            self.osu_dir = try std.heap.page_allocator.allocSentinel(win.WCHAR, path.len, 0);

            for (path, 0..) |c, i| { // Copy over
                self.osu_dir[i] = c;
            }

            // I believe I can free `path` since its not being used anymore but we'll see about it
        }

        pub fn getOsuSongsPath(self: *ProcReader) !void {
            _ = self;
        }

        pub fn memReadInit(self: *ProcReader) !void {
            _ = self;
        }

        pub fn memReadDeinit(self: *ProcReader) void {
            _ = self;
        }

        pub fn mapReadInit(self: *ProcReader) !void {
            _ = self;
        }

        pub fn mapReadDeinit(self: *ProcReader) void {
            _ = self;
        }

        pub fn memRead(self: *ProcReader, base: usize, buffer: *[]u8) !void {
            _ = self;
            _ = base;
            _ = buffer;
            //
        }

        pub fn memFindPat(self: *ProcReader, needle: []u8) ![2]u32 {
            _ = self;
            _ = needle;
        }

        pub fn toStr(self: *ProcReader) ![]u8 { // Just a test fn
            try self.findOsuProc();
            return ProcReadErr.OsuProcDNE;
        }
    },
    else => @compileError("Compilation for this platform is currently not supported.\nPlease file an issue on github if either you believe you shouldn't be seeing this message or would like for your platform to be supported!\n"),
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

inline fn u8ArrToU16Arr(in: *const []u8) ![]u16 {
    if (in.*.len & 0x1 == 0x1) {
        std.debug.print("Odd length array {}... can't convert to u16 properly\n", .{in.len});
        return ProcReadErr.FailedToConvertU8ToU16;
    }

    const new_len: usize = @divFloor(in.*.len, 2);

    const out = try std.heap.page_allocator.alloc(u16, new_len);

    var i: usize = 1;
    var j: usize = 0;

    while (i < in.*.len) : (i += 2) {
        var wchar: u16 = in.*[i];
        wchar <<= 8;
        wchar |= in.*[i - 1];
        out[j] = wchar;
        j += 1;
    }
    return out;
}
