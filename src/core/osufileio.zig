const std = @import("std");
const fs = std.fs;
const heap = std.heap;
const fmt = std.fmt;

const sv = @import("../core/libsv.zig");
const hitobj = @import("../core/hitobj.zig");

const stdout_file = std.io.getStdOut().writer();
var bw = std.io.bufferedWriter(stdout_file);
const stdout = bw.writer();

const OsuFileIOError = error{
    FileDNE,
    FileTooLarge, // If the file is too big to work on
    IncompleteFile, // If the file either ends in an unexpected place or does not have some vital data (ex. missing metadata fields)
    InvalidType,
};

const OsuSectionError = error{
    SectionDoesNotExist, // Trying to access a section that does not exist
    FoundTooManySections, // If more than 8 sections are found
};

const OsuObjErr = error{
    FoundTooManyFields,
    PointDNE,
};

const HEADER_MAP = [_][]const u8{ "General", "Editor", "Metadata", "Difficulty", "Events", "TimingPoints", "HitObjects" };

pub const OsuFile = struct {
    path: []u8,
    file: ?fs.File,
    //metadata: meta.Metadata,
    section_offsets: [7]usize,
    section_end_offsets: [7]usize,
    curr_offsets: [7]usize,

    // Basically a constructor
    pub fn init(self: *OsuFile, path: []const u8) !void {
        if (std.ascii.eqlIgnoreCase(path, "NONE")) return OsuFileIOError.FileDNE;

        self.path = try heap.raw_c_allocator.alloc(u8, path.len);
        @memcpy(self.path, path);

        self.file = try fs.openFileAbsolute(self.path, .{ .mode = .read_write });

        // Get metadata here
        try self.findSectionOffsets();
        for (self.section_offsets, 0..self.section_offsets.len) |s, i| self.curr_offsets[i] = s;
    }

    // Destructor
    pub fn deinit(self: *OsuFile) void {
        self.file.?.close();
        heap.raw_c_allocator.free(self.path);
    }

    // Reset all offsets and seek to the head of the file
    pub fn reset(self: *OsuFile) !void {
        for (self.section_offsets, 0..self.section_offsets.len) |o, i| self.curr_offsets[i] = o;
        if (self.file) |fp| {
            try fp.seekTo(0);
        }
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
    pub fn createBackup(self: *OsuFile) !void {
        _ = self;
    }

    // Returns the byte offset of the starting line, ending line, and the number of points found
    pub fn extentsOfSection(self: *OsuFile, lower: i32, upper: i32, mode: anytype) ![3]u64 {
        if (self.file == null) return OsuFileIOError.FileDNE;
        var buffer = [_]u8{0} ** 64;
        var retval = [_]u64{0} ** 3;
        var m: usize = 0; // mode
        var t: u2 = 0; // where is the 'time' field located
        var bytes_read: usize = 64;
        var last_in_range = false; // Explained below

        // _____--------____
        //      ^      ^
        //      1      2
        // 1 = f->t transition | start of section
        // 2 = t->f transition | end of section

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
        _while: while (bytes_read >= 64) {
            var field: u2 = 0;
            var field_buf = [_]u8{0} ** 32; // The longest time value I could find was 17 chars long
            var i_fb: usize = 0;

            bytes_read = try self.file.?.readAll(&buffer);

            _for: for (buffer, 0..buffer.len) |c, i| {
                switch (c) {
                    '\n' => { // FUCK YOU BILL GOD DAMN IT I HATE \r\n
                        if (i < 2) break :_while; // This means we reached the end of the section | hopefully this prevents \r\n

                        // Not sure if i actually need this
                        //try self.file.?.seekBy(@as(i64, @intCast(i)) - @as(i64, @intCast(bytes_read)) + 2); // Seek back
                        //break :_for; // Start over

                    },
                    ',' => blk: {
                        if (field < t) {
                            field += 1;
                            i_fb = 0;
                            @memset(&field_buf, 0);
                        } else {
                            const found_time = try std.fmt.parseInt(i32, field_buf[0..i_fb], 10); // Just to make this next bit readable

                            if (lower <= found_time and found_time <= upper) {
                                if (!last_in_range) retval[0] = try self.file.?.getPos() - 65; // f->t transition
                                last_in_range = true;
                                retval[2] += 1;
                            } else {
                                if (last_in_range) {
                                    retval[1] = try self.file.?.getPos() - 64; // Move the end point along
                                    break :_while; // t->f transition marks the end of the section
                                }
                            }
                            try self.file.?.seekBy(0 - (@as(i64, @intCast(bytes_read - (std.ascii.indexOfIgnoreCase(&buffer, &[_]u8{'\n'}) orelse 0) - 1)))); // Skip to the end of the line
                            break :_for;
                        }

                        break :blk;
                    },

                    else => {
                        field_buf[i_fb] = c;
                        i_fb += 1;
                    },
                }
            }
        }

        try self.file.?.seekTo(self.curr_offsets[m]); // Move the cursor back to where it was last

        return retval;
    }

    pub fn posOfPoint(self: *OsuFile, time: i32, mode: anytype) !?u64 {
        const i = self.extentsOfSection(time, time, mode) catch |e| return e; // Pass it back
        if (i[0]) |j| return j else return null;
    }

    // TODO: remove append and just use replace.you can do the same thing as it by doing placeSection(end_of_sec, end_of_sec, arr)
    pub fn placeSection(self: *OsuFile, start: u64, end: u64, arr: anytype, mode: enum { replace, append }) !void {
        if (self.file == null) return OsuFileIOError.FileDNE;

        // This is fucked... just let me use an if statement please
        _ = switch (@TypeOf(arr)) {
            []sv.TimingPoint, []hitobj.HitObject => 0,
            else => unreachable,
        };

        var len = self.path.len;

        for (0..len) |i| {
            if (self.path[self.path.len - 1 - i] == '/') break;
            len -= 1;
        }

        const tmp_pref: []u8 = try heap.raw_c_allocator.alloc(u8, len);
        @memcpy(tmp_pref, self.path[0..len]);
        const tmp_path = try std.mem.concat(heap.raw_c_allocator, u8, &[_][]u8{ tmp_pref, @constCast("tmp.txt") });
        defer heap.raw_c_allocator.free(tmp_path);

        const tmpfp: fs.File = try fs.createFileAbsolute(tmp_path, .{ .read = true, .truncate = true });

        try self.file.?.seekTo(0);

        var t = [_]u8{0};
        var l: u64 = 1;
        for (0..start) |_| {
            _ = try self.file.?.readAll(&t);
            _ = try tmpfp.writeAll(&t);
        }
        if (t[0] == '\r') try tmpfp.writeAll(&[_]u8{10});

        // Insert the new stuff
        for (arr) |a| {
            _ = try tmpfp.writeAll(try a.toStr());
        }

        if (mode == .replace) try self.file.?.seekTo(end); // pick at the end of the section we want to replace

        while (l == 1) {
            l = try self.file.?.readAll(&t);
            _ = try tmpfp.writeAll(&t);
        }
        // Switch the files out
        self.file.?.close();
        tmpfp.close();

        try fs.renameAbsolute(tmp_path, self.path); // Move

        // This shouldn't cause a leak I think?
        self.file = try fs.openFileAbsolute(self.path, .{ .mode = .read_write });
        try self.findSectionOffsets();
    }

    // Shitty internal fn
    inline fn isEq(a: []const u8, b: []const u8) bool {
        for (a, 0..a.len) |c, i| if (c != b[i]) return false;
        return true;
    }

    pub fn findEndOfSectionOffset(self: *OsuFile, offset: u64) !u64 {
        if (self.file == null) return OsuFileIOError.FileDNE;
        var buffer = [_]u8{0} ** 64;
        var bytes_read: u64 = 64;

        try self.file.?.seekTo(offset + 2);

        _while: while (bytes_read > 0) {
            const i = std.ascii.indexOfIgnoreCase(&buffer, &[_]u8{'\n'});
            if (i) |j| {
                if (j < 2) {
                    try self.file.?.seekBy(0 - (@as(i64, @intCast(bytes_read - j - 1))));
                    break :_while;
                }
                try self.file.?.seekBy(0 - (@as(i64, @intCast(bytes_read - j - 1))));
            }
            bytes_read = try self.file.?.readAll(&buffer);
        }
        return try self.file.?.getPos() - 2;
    }

    // Get section offsets for the .osu file
    pub fn findSectionOffsets(self: *OsuFile) !void {
        var buffer = [_]u8{0} ** 512;
        var header_buf = [_]u8{0} ** 16;

        if (self.file == null) return OsuFileIOError.FileDNE;

        // Check if the file is too big
        // TODO: This is kinda stupid... think about removing it... | ... yea fuck this
        //const file_size: u64 = try self.file.?.getEndPos();
        //if ((file_size / 1024) >= 1500) { // Don't want to spend forever processing and or hog a ton or memory
        //    std.debug.print("\x1b[31mERROR: This file is WAAAYY too large to work on... (1.5Mb)\x1b[0m\n", .{});
        //    return OsuFileIOError.FileTooLarge; // Return an error
        //}

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
};

const BLOCK_SZ = 128; // This is kinda dumb

pub fn load() type {
    return struct {
        var buffer = [_]u8{0} ** 64;
        var str_buff = [_]u8{0} ** 64;
        var i_strbuf: u8 = 0;

        inline fn StrToTimingPoint() !sv.TimingPoint {
            var point = sv.TimingPoint{};
            var buf = [_]u8{0} ** 64;

            var field: u8 = 0; // Current field we're filling out
            var i_buf: u8 = 0; // Current index in the buf

            for (buffer) |c| { // Loop through the given string char by char
                if (c == ',') { // ',' denotes end of field
                    switch (field) { // Figure out which field we're on
                        0 => blk: {
                            point.time = try fmt.parseInt(i32, buf[0..i_buf], 10); // Need to use a slice or the function will try and translate the blank spots of the buf, resulting in an error
                            break :blk;
                        },
                        1 => blk: {
                            point.value = try fmt.parseFloat(f32, buf[0..i_buf]);
                            break :blk;
                        },
                        2 => blk: {
                            point.meter = try fmt.parseUnsigned(u8, buf[0..i_buf], 10);
                            break :blk;
                        },
                        3 => blk: {
                            point.sampleSet = try fmt.parseUnsigned(u8, buf[0..i_buf], 10);
                            break :blk;
                        },
                        4 => break, // Unneeded
                        5 => blk: {
                            point.volume = try fmt.parseUnsigned(u8, buf[0..i_buf], 10);
                            break :blk;
                        },
                        6 => blk: {
                            point.is_inh = try fmt.parseUnsigned(u1, buf[0..i_buf], 10);
                            break :blk;
                        },
                        7 => blk: {
                            point.effects = try fmt.parseUnsigned(u8, buf[0..i_buf], 10);
                            break :blk;
                        },
                        else => {
                            return OsuObjErr.FoundTooManyFields;
                        },
                    }
                    field += 1; // Increment the field
                    i_buf = 0; // Set the buf index to 0
                    @memset(&buf, 0);
                } else {
                    buf[i_buf] = c;
                    i_buf += 1;
                }
            }
            return point;
        }

        inline fn StrToHitObject() !hitobj.HitObject {
            var field: u8 = 0; // Current field we're filling out
            var i_buf: u8 = 0; // Current index in the buf
            var hit = hitobj.HitObject{};
            var buf = [_]u8{0} ** 64;
            for (buffer, 0..buffer.len) |c, i| { // Loop through the given string char by char
                if ((c == ',' and field < 5) or i == buffer.len - 1) { // Trying to keep the ',' triggering when reading the sliders
                    switch (field) { // Figure out which field we're on and apply the right function to it
                        0 => blk: {
                            hit.x = try fmt.parseInt(i32, buf[0..i_buf], 10);
                            break :blk;
                        },
                        1 => blk: {
                            hit.y = try fmt.parseInt(i32, buf[0..i_buf], 10);
                            break :blk;
                        },
                        2 => blk: {
                            hit.time = try fmt.parseInt(i32, buf[0..i_buf], 10);
                            break :blk;
                        },
                        3 => blk: {
                            hit.type = try fmt.parseUnsigned(u8, buf[0..i_buf], 10);
                            break :blk;
                        },
                        4 => blk: {
                            hit.hitSound = try fmt.parseUnsigned(u8, buf[0..i_buf], 10);
                            break :blk;
                        },
                        5 => blk: {
                            @memcpy(hit.objectParams[0..i_buf], buf[0..i_buf]); // This should copy the bytes of buf into objectParams
                            break :blk;
                        },
                        else => {
                            return OsuObjErr.FoundTooManyFields;
                        },
                    }
                    field += 1; // Increment the field
                    i_buf = 0; // Set the buf index to 0
                    @memset(&buf, 0);
                } else {
                    buf[i_buf] = c;
                    i_buf += 1;
                }
            }
            return hit;
        }

        pub fn hitObjArray(file: fs.File, offset: u64, size: usize, hitobj_array: *[]hitobj.HitObject) !u64 {
            hitobj_array.* = if (size != 0) (try heap.raw_c_allocator.alloc(hitobj.HitObject, size)) else (try heap.raw_c_allocator.alloc(hitobj.HitObject, BLOCK_SZ)); // Allocate `size` elements if specified. else realloc as much as necessary

            try file.seekTo(offset + 1); // Go to the offset

            for (0..hitobj_array.*.len) |curr_point| {
                const bytes_read = try file.readAll(&buffer); // Read in the new data
                if (bytes_read < buffer.len) { // If we read less than the buffer can hold, then we must be at the end
                    return OsuFileIOError.IncompleteFile;
                }
                for (buffer, 0..buffer.len) |c, i| {
                    if (c <= '\r') {
                        hitobj_array.*[curr_point] = try StrToHitObject(); // Convert the string and load it into the array
                        try file.seekBy(@as(i64, @intCast(i)) - @as(i64, @intCast(bytes_read)) + 2); // Seek back the difference so that we don't miss data.
                        i_strbuf = 0; // Set this iterator to 0
                        @memset(&str_buff, 0); // Clear out the string buffer
                        break;
                    } else {
                        str_buff[i_strbuf] = c;
                        i_strbuf += 1;
                    }
                }
                @memset(&buffer, 0); // Clear the buffer
            }

            return try file.getPos() - 1; // Return the last position
        }

        pub fn timingPointArray(file: fs.File, offset: u64, size: usize, sv_array: *[]sv.TimingPoint) !u64 {
            sv_array.* = if (size != 0) (try heap.raw_c_allocator.alloc(sv.TimingPoint, size)) else (try heap.raw_c_allocator.alloc(sv.TimingPoint, BLOCK_SZ)); // Allocate `size` elements if specified. else realloc as much as necessary

            try file.seekTo(offset + 1); // Go to the offset

            for (0..sv_array.len) |curr_point| {
                const bytes_read = try file.readAll(&buffer);
                if (bytes_read < buffer.len) { // If we read less than the buffer can hold, then we must be at the end
                    return OsuFileIOError.IncompleteFile;
                }
                for (buffer, 0..buffer.len) |c, i| {
                    if (c <= '\r') {
                        sv_array.*[curr_point] = try StrToTimingPoint(); // Convert the string and load it into the array
                        try file.seekBy(@as(i64, @intCast(i)) - @as(i64, @intCast(bytes_read)) + 2); // Seek back the difference so that we don't miss data.
                        i_strbuf = 0; // Set this iterator to 0
                        @memset(&str_buff, 0); // Clear out the string buffer
                        break;
                    } else {
                        str_buff[i_strbuf] = c;
                        i_strbuf += 1;
                    }
                }
                @memset(&buffer, 0); // Clear the buffer
            }

            return try file.getPos() - 1; // Return the last position
        }
    };
}
