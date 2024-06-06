const std = @import("std");
const builtin = @import("builtin");
const fs = std.fs;
const mem = std.mem;
const fmt = std.fmt;

const sv = @import("../core/sv.zig");
const hitobj = @import("../core/hitobj.zig");
const meta = @import("./metadata.zig");

const stdout_file = std.io.getStdOut().writer();
var bw = std.io.bufferedWriter(stdout_file);
const stdout = bw.writer();

pub const OsuFileIOError = error{
    FileDNE,
    NoPathGiven,
    FileTooLarge, // If the file is too big to work on
    IncompleteFile, // If the file either ends in an unexpected place or does not have some vital data (ex. missing metadata fields)
    InvalidType,
};

pub const OsuSectionError = error{
    SectionDoesNotExist, // Trying to access a section that does not exist
    FoundTooManySections, // If more than 8 sections are found
};

pub const OsuObjErr = error{
    FoundTooManyFields,
    PointDNE,
    NoPointsGiven,
};

const HEADER_MAP = [_][]const u8{ "General", "Editor", "Metadata", "Difficulty", "Events", "TimingPoints", "HitObjects" };

pub const OsuFile = struct {
    path: []u8,
    file: ?fs.File,
    metadata: meta.Metadata,
    section_offsets: [7]usize,
    section_end_offsets: [7]usize,
    curr_offsets: [7]usize,

    // Basically a constructor
    // TODO: MAKE THIS CROSS PLATFORM | REPLACE ALL '/' WITH SOME DYNAMIC SHIT
    pub fn init(self: *OsuFile, path: []u8) !void {
        std.debug.print("PATH: {s}\n", .{path});
        if (std.ascii.eqlIgnoreCase(path, "NONE")) return OsuFileIOError.FileDNE;

        self.path = try std.heap.page_allocator.alloc(u8, path.len);
        @memcpy(self.path, path);
        std.debug.print("SPATH: {s}\n", .{self.path});

        self.file = fs.openFileAbsolute(self.path, .{ .mode = .read_write }) catch {
            return OsuFileIOError.NoPathGiven;
        };

        try self.findSectionOffsets();
        for (self.section_offsets, 0..self.section_offsets.len) |s, i| self.curr_offsets[i] = s;

        // TODO: This next bit is utterly retarded... how about no... you can do better
        const eos = try self.findEndOfSectionOffset(self.section_offsets[2]);
        const metadata_sect: []u8 = try std.heap.page_allocator.alloc(u8, eos - self.section_offsets[2]);
        defer std.heap.page_allocator.free(metadata_sect);

        try self.file.?.seekTo(self.section_offsets[2]);
        _ = try self.file.?.readAll(metadata_sect);

        try self.metadata.init(metadata_sect);
    }

    // Destructor
    pub fn deinit(self: *OsuFile) void {
        self.file.?.close();
        self.metadata.deinit();
        std.heap.page_allocator.free(self.path);
    }

    // Reset all offsets and seek to the head of the file
    pub fn reset(self: *OsuFile) !void {
        for (self.section_offsets, 0..self.section_offsets.len) |o, i| self.curr_offsets[i] = o;
        if (self.file) |fp| {
            try fp.seekTo(0);
        }
    }

    pub fn refresh(self: *OsuFile) !void {
        self.file.?.close();
        self.file = try fs.openFileAbsolute(self.path, .{ .mode = .read_write });
    }

    // Write changes to disk
    pub fn save(self: *OsuFile) !void {
        if (self.file == null) return OsuFileIOError.FileDNE;
        try self.file.?.sync();
    }

    // Create a backup of the original file
    // Save that and the original to disk under different names
    // Probably like "diffname" -> "diffname-backup-TIMESTAMP"
    // Probably timestamp of sec+min+hour+day+mon+year
    pub fn createBackup(self: *OsuFile) ![]u8 {
        var len = self.path.len;

        for (0..len) |i| {
            switch (builtin.os.tag) {
                .windows => {
                    if (self.path[self.path.len - 1 - i] == '\\') break;
                },
                else => {
                    if (self.path[self.path.len - 1 - i] == '/') break;
                },
            }
            len -= 1;
        }

        const bckup_v_name = try self.metadata.genBackupVerName();
        const bckup_f_name = try self.metadata.genBackupFileName();

        const tmp_pref: []u8 = try std.heap.page_allocator.alloc(u8, len);
        @memcpy(tmp_pref, self.path[0..len]);
        const tmp_path = try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ tmp_pref, bckup_f_name });
        //defer std.heap.page_allocator.free(tmp_path);

        const tmpfp: fs.File = try fs.createFileAbsolute(tmp_path, .{ .read = true, .truncate = true });

        // then basically the same procedure as place section but this time with the metadata

        const last_loc: usize = @intCast(try self.file.?.getPos()); // save this

        const eos = try self.findEndOfSectionOffset(self.section_offsets[2]);
        try self.file.?.seekTo(0);

        var t = [_]u8{0};

        // Copy up to the section
        while (@as(usize, @intCast(try self.file.?.getPos())) <= self.section_offsets[2]) {
            _ = try self.file.?.read(&t);
            _ = try tmpfp.write(&t);
        }

        // Then insert new metadata

        // TODO: This is bad
        // Make a function to return a properly formatted string given a field or something
        _ = try tmpfp.writeAll(try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ @constCast("Title:"), self.metadata.title, @constCast("\r\n") }));
        _ = try tmpfp.writeAll(try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ @constCast("TitleUnicode:"), self.metadata.title_unicode, @constCast("\r\n") }));
        _ = try tmpfp.writeAll(try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ @constCast("Artist:"), self.metadata.artist, @constCast("\r\n") }));
        _ = try tmpfp.writeAll(try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ @constCast("ArtistUnicode:"), self.metadata.artist_unicode, @constCast("\r\n") }));
        _ = try tmpfp.writeAll(try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ @constCast("Creator:"), self.metadata.creator, @constCast("\r\n") }));
        _ = try tmpfp.writeAll(try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ @constCast("Version:"), bckup_v_name, @constCast("\r\n") }));
        _ = try tmpfp.writeAll(try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ @constCast("Source:"), self.metadata.source, @constCast("\r\n") }));
        _ = try tmpfp.writeAll(try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ @constCast("Tags:"), self.metadata.tags, @constCast("\r\n") }));
        _ = try tmpfp.writeAll(try fmt.allocPrint(std.heap.page_allocator, "BeatmapID:{}\r\n", .{self.metadata.beatmap_id}));
        _ = try tmpfp.writeAll(try fmt.allocPrint(std.heap.page_allocator, "BeatmapSetID:{}\r\n", .{self.metadata.set_id}));

        // Now pick up from where the section ended
        try self.file.?.seekTo(eos);

        while (try self.file.?.read(&t) != 0) {
            _ = try tmpfp.write(&t);
        }

        tmpfp.close(); // Close the file

        try self.file.?.seekTo(last_loc); // Go back
        return tmp_path;
    }

    pub fn extentsOfSection(self: *OsuFile, lower: i32, upper: i32, mode: anytype) ![3]usize {
        if (self.file == null) return OsuFileIOError.FileDNE;
        var retval = [_]usize{0} ** 3;
        var m: usize = 0; // mode
        var t: u2 = 0; // where is the 'time' field located
        var bytes_read: usize = 64;
        var last_in_range = false;

        switch (mode) {
            sv.TimingPoint => {
                m = 5;
                t = 0;
            },
            hitobj.HitObject => {
                m = 6;
                t = 2;
            },
            else => return OsuFileIOError.InvalidType,
        }
        try self.file.?.seekTo(self.section_offsets[m] + 1);

        // This feels cursed
        // TODO: this is fucked up redo it | little bit better but still fucked
        _line: while (bytes_read != 0) {
            var buffer = [_]u8{0} ** 64;
            var i_b: usize = 0;
            var f: usize = 0;

            bytes_read = try self.file.?.readAll(&buffer);
            const eol = std.ascii.indexOfIgnoreCase(&buffer, &[_]u8{'\n'}) orelse bytes_read;
            //std.debug.print("GOT: `{s}`\n", .{buffer});
            var last_i_b: usize = 0;

            _char: while (eol != 0) {
                i_b = std.ascii.indexOfIgnoreCasePos(&buffer, i_b + 1, &[_]u8{','}) orelse break :_char; // Next instance of ,
                if (i_b >= eol) break :_char; // We shouldnt be reading past the end
                if (f == t) { // if the current field == the target
                    const found_time = try std.fmt.parseInt(i32, buffer[last_i_b..i_b], 10);
                    std.debug.print("Found point at `{}`\n", .{found_time});
                    //std.debug.print("\tBounds: `{}`->`{}`\n", .{ lower, upper });
                    if (lower <= found_time and found_time <= upper) {
                        if (!last_in_range) {
                            retval[0] = @intCast(try self.file.?.getPos() - bytes_read); // f->t transition
                            //std.debug.print("First!\n", .{});
                        }
                        last_in_range = true;
                        retval[2] += 1;
                        //std.debug.print("Found point!\n", .{});
                    } else {
                        if (last_in_range or found_time > upper) {
                            //if (found_time > upper) { // This should be saying the same thing
                            retval[1] = @intCast(try self.file.?.getPos() - bytes_read); // Set the cursor at the start of the line
                        } else {
                            retval[0] = @intCast(((try self.file.?.getPos() - bytes_read)) + eol); // Set the cursor at the end of the current line
                        }
                    }
                    break :_char;
                } else f += 1;
                last_i_b = i_b + 1;
            }
            if (eol < 15 or retval[1] != 0) break :_line;
            try self.file.?.seekBy(0 - (@as(isize, @intCast(bytes_read - eol - 1))));
        }

        if (retval[1] == 0) retval[1] = try self.findEndOfSectionOffset(self.section_offsets[m] + 1); // If no ending val just set the cursor to EOS
        if (retval[0] == 0) retval[0] = try self.findEndOfSectionOffset(self.section_offsets[m] + 1); // Same w/ start

        // DEBUG
        try self.file.?.seekTo(retval[0] - 3);
        std.debug.print("START:{}:", .{retval[0]});
        for (0..20) |_| {
            var b = [_]u8{0};
            _ = try self.file.?.read(&b);
            if (b[0] > 32) {
                std.debug.print("{c}", .{b[0]});
            } else {
                std.debug.print("`_{}`", .{b[0]});
            }
        }
        std.debug.print("\n", .{});

        try self.file.?.seekTo(retval[1] - 3);
        std.debug.print("END:{}:", .{retval[1]});
        for (0..20) |_| {
            var b = [_]u8{0};
            _ = try self.file.?.read(&b);
            if (b[0] > 32) {
                std.debug.print("{c}", .{b[0]});
            } else {
                std.debug.print("`_{}`", .{b[0]});
            }
        }
        std.debug.print("\n", .{});
        //DEBUG

        try self.file.?.seekTo(self.curr_offsets[m]); // Move the cursor back to where it was last
        return retval;
    }

    pub fn findSectionInitialBPM(self: *OsuFile, offset: usize) ![2]f32 {
        var buffer = [_]u8{0} ** 64;
        var bytes_read: usize = 0;
        var fields: u3 = 0;
        var bpmlineoffset: usize = 0;
        var bpmoffset = [_]usize{ 0, 0 };
        bpmoffset[0] = 1;

        try self.file.?.seekTo(self.section_offsets[5]);

        // FIXME: this needs offset of line AFTER start s.t. sving a section beginning on a barline at the start of a song doesnt die
        while (@as(usize, @intCast(try self.file.?.getPos())) <= offset) {
            bytes_read = try self.file.?.readAll(&buffer);
            _for: for (buffer, 0..buffer.len) |c, i| {
                switch (c) {
                    '\n' => {
                        try self.file.?.seekBy(@as(isize, @intCast(i)) - @as(isize, @intCast(bytes_read)) + 2); // Seek back
                        break :_for; // Start over
                    },
                    ',' => {
                        switch (fields) {
                            6 => {
                                if (buffer[i - 1] == '1') bpmlineoffset = @as(usize, @intCast(try self.file.?.getPos())) - bytes_read;
                                try self.file.?.seekBy(0 - (@as(isize, @intCast(bytes_read - (std.ascii.indexOfIgnoreCase(&buffer, &[_]u8{'\n'}) orelse 0) - 1)))); // Skip to the end of the line
                                break :_for;
                            },
                            else => fields += 1,
                        }
                    },
                    else => continue :_for,
                }
            }
            fields = 0;
            @memset(&buffer, 0);
        }

        if (bpmlineoffset == 0) return OsuObjErr.PointDNE;

        try self.file.?.seekTo(bpmlineoffset);
        _ = try self.file.?.readAll(&buffer);

        fields = 0;
        _for: for (buffer, 0..buffer.len) |c, i| { // Find where the value section is located
            switch (c) {
                ',' => {
                    switch (fields) {
                        0 => bpmoffset[0] = i + 1,
                        1 => {
                            bpmoffset[1] = i;
                            break :_for;
                        },
                        else => return OsuObjErr.FoundTooManyFields,
                    }
                },
                else => continue,
            }
            fields += 1;
        }
        //std.debug.print("BPMRET: {s}, {s}\n", .{ buffer[bpmoffset[0]..bpmoffset[1]], buffer[0 .. bpmoffset[0] - 1] });
        return [2]f32{ 60000.0 / try fmt.parseFloat(f32, buffer[bpmoffset[0]..bpmoffset[1]]), try fmt.parseFloat(f32, buffer[0 .. bpmoffset[0] - 1]) };
    }

    pub fn posOfPoint(self: *OsuFile, time: i32, mode: anytype) !?usize {
        const i = self.extentsOfSection(time, time, mode) catch |e| return e; // Pass it back
        if (i[0]) |j| return j else return null;
    }

    pub fn placeSection(self: *OsuFile, start: usize, end: usize, arr: anytype) !void {
        std.debug.print("IN: placeSection\n", .{});
        if (self.file == null) return OsuFileIOError.FileDNE;

        // This is fucked... just let me use an if statement please
        _ = switch (@TypeOf(arr)) {
            []sv.TimingPoint, []hitobj.HitObject => 0,
            else => unreachable,
        };

        var len = self.path.len;

        for (0..len) |i| {
            switch (builtin.os.tag) {
                .windows => {
                    if (self.path[self.path.len - 1 - i] == '\\') break;
                },
                else => {
                    if (self.path[self.path.len - 1 - i] == '/') break;
                },
            }
            len -= 1;
        }

        std.debug.print("Allocing for file name\n", .{});
        const tmp_pref: []u8 = try std.heap.page_allocator.alloc(u8, len);
        std.debug.print("Copying path\n", .{});
        @memcpy(tmp_pref, self.path[0..len]);
        std.debug.print("Creating path\n", .{});
        const tmp_path = try std.mem.concat(std.heap.page_allocator, u8, &[_][]u8{ tmp_pref, @constCast("tmp.txt") });
        defer std.heap.page_allocator.free(tmp_path);

        std.debug.print("Creating file at path\n", .{});
        const tmpfp: fs.File = try fs.createFileAbsolute(tmp_path, .{ .read = true, .truncate = true });

        try self.file.?.seekTo(0);

        std.debug.print("Copying old conts\n", .{});
        var t = [_]u8{0};
        var l: usize = 1;
        for (0..start) |_| {
            _ = try self.file.?.readAll(&t);
            _ = try tmpfp.writeAll(&t);
        }
        if (t[0] == '\r') try tmpfp.writeAll(&[_]u8{10});

        // Insert the new stuff
        std.debug.print("Inserting new: arr.len = {}\n", .{arr.len});
        for (arr) |a| {
            const s = try a.toStr();
            defer std.heap.page_allocator.free(s);
            _ = try tmpfp.writeAll(s);
        }

        try self.file.?.seekTo(end); // pick at the end of the section we want to replace

        std.debug.print("Resuming\n", .{});
        while (l == 1) {
            l = try self.file.?.readAll(&t);
            _ = try tmpfp.writeAll(&t);
        }
        // Switch the files out
        self.file.?.close();
        tmpfp.close();

        std.debug.print("Overwriting old file\n", .{});
        try fs.renameAbsolute(tmp_path, self.path); // Move

        // This shouldn't cause a leak I think?
        std.debug.print("Fixing struct file descriptor\n", .{});
        self.file = try fs.openFileAbsolute(self.path, .{ .mode = .read_write });
        std.debug.print("Finding new section offsets\n", .{});
        try self.findSectionOffsets();
    }

    // TODO: While this looks nicer than the previous implementation...
    //       This is really unoptimized and runs in like factorial time or some shit
    pub fn findEndOfSectionOffset(self: *OsuFile, offset: usize) !usize {
        if (self.file == null) return OsuFileIOError.FileDNE;
        var buffer = [_]u8{0} ** 64;
        var bytes_read: usize = 64;

        try self.file.?.seekTo(offset + 2);

        _while: while (bytes_read > 0) {
            const eol = std.ascii.indexOfIgnoreCase(&buffer, &[_]u8{'\n'});
            if (eol) |e| {
                if (e < 2) {
                    try self.file.?.seekBy(0 - (@as(isize, @intCast(bytes_read - e - 1))));
                    break :_while;
                }
                try self.file.?.seekBy(0 - (@as(isize, @intCast(bytes_read - e - 1))));
            }
            bytes_read = try self.file.?.readAll(&buffer);
        }
        return @as(usize, @intCast(try self.file.?.getPos())) - 2;
    }

    // Get section offsets for the .osu file
    pub fn findSectionOffsets(self: *OsuFile) !void {
        var buffer = [_]u8{0} ** 512;
        var header_buf = [_]u8{0} ** 16;

        if (self.file == null) return OsuFileIOError.FileDNE;

        // Warn if file is really big
        const file_size: usize = @intCast(try self.file.?.getEndPos());
        if ((file_size / 1024) >= 1500) { // Don't want to spend forever processing and or hog a ton or memory
            std.debug.print("\x1b[33mWARNING: What the hell man...\nWhy are you editing nanaparty with this shitty tool\n(File size exceeds 1.5Mb)\x1b[0m\n", .{});
            return OsuFileIOError.FileTooLarge; // Return an error
        }

        try self.file.?.seekTo(0); // Make sure we're at the start

        var bytes_read: usize = buffer.len; // Holds how many bytes we just read
        var j: usize = 0; // Count the passes we made in order to calculate the offset properly
        var r: bool = false; // true = should be reading a header section
        var i_r: usize = 0;

        while (bytes_read >= buffer.len) { // If we have read less than 512 bytes then we have hit the end of the file
            bytes_read = try self.file.?.readAll(&buffer);
            for (buffer, 1..buffer.len + 1) |c, k| { // Read char by char to find the end of a header section
                switch (c) {
                    '[' => r = true,
                    ']' => blk: {
                        if (r) {
                            for (HEADER_MAP, 0..HEADER_MAP.len) |h, i| {
                                if (isEq(h, &header_buf)) self.section_offsets[i] = (512 * j) + 1 + k;
                            }
                        }
                        r = false;
                        i_r = 0;
                        break :blk;
                    },
                    else => blk: {
                        if (r) {
                            header_buf[i_r] = c;
                            i_r += 1;
                        }
                        break :blk;
                    },
                }
            }
            @memset(&buffer, 0);
            j += 1;
        }
    }

    // Strongly typed languages when `anytype`
    pub fn loadObjArr(self: *OsuFile, offset: usize, size: usize, arr: anytype) !void {
        _ = switch (@TypeOf(arr)) {
            *[]sv.TimingPoint, *[]hitobj.HitObject => 0,
            else => unreachable,
        };
        var buffer = [_]u8{0} ** 64;

        arr.* = if (size != 0) (try std.heap.page_allocator.alloc(@TypeOf(arr.*[0]), size)) else return //OsuObjErr.NoPointsGiven;

        std.debug.print("loadObjArr: OFFSET = {}\n", .{offset});
        try self.file.?.seekTo(offset);

        var bytes_read = buffer.len;

        _for: for (0..arr.*.len) |i| {
            bytes_read = try self.file.?.readAll(&buffer);
            if (bytes_read == 0) break :_for;

            const eol = if (std.ascii.indexOfIgnoreCase(&buffer, &[_]u8{ '\r', '\n' })) |e| e else buffer.len - 2; // -2 to compensate to the + 2 later on

            if (eol < 15) { // the shortest possible line you could create is 15 chars long
                if (bytes_read >= 64) {
                    std.debug.print("INCOMPLETE BUFFER: {s}\n", .{buffer});
                    return OsuFileIOError.IncompleteFile; // this is only true if we are at the end of a section
                }
                continue;
            }

            try arr.*[i].fromStr(buffer[0 .. eol + 2]);
            @memset(&buffer, 0);

            try self.file.?.seekBy(0 - @as(isize, @intCast(bytes_read - eol - 2)));
        }

        // Set the proper current offset based off the type of array given
        switch (@TypeOf(arr)) {
            *[]sv.TimingPoint => self.curr_offsets[5] = @intCast(try self.file.?.getPos()),
            *[]hitobj.HitObject => self.curr_offsets[6] = @intCast(try self.file.?.getPos()),
            else => unreachable,
        }
    }
};

// Shitty internal fn
inline fn isEq(a: []const u8, b: []const u8) bool {
    for (a, 0..a.len) |c, i| if (c != b[i]) return false;
    return true;
}
