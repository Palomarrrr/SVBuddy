const std = @import("std");
const osufile = @import("./osufileio.zig");
const com = @import("../util/common.zig");

const std_allocator = com.std_allocator;

const MetadataSectionErr = error{
    InvalidField,
};

const SECTION_LABELS = [_][]const u8{ "", "Title", "TitleUnicode", "Artist", "ArtistUnicode", "Creator", "Version", "Source", "Tags", "BeatmapID", "BeatmapSetID" };

pub const Metadata = struct {
    title: []u8,
    title_unicode: []u8,
    artist: []u8,
    artist_unicode: []u8,
    creator: []u8,
    version: []u8,
    source: []u8,
    //tags: [][]u8, // TODO: IMPLEMENT AS [][]u8
    tags: []u8,
    beatmap_id: u32,
    set_id: i32,

    // Takes in the entire [Metadata] section as an arg | EXCLUDING THE [Metadata] header
    // Parses everything out, allocates space, and inserts
    // it into the newly created Metadata struct
    pub fn init(self: *Metadata, metadata_section: []u8) !void {
        var buffer = [_]u8{0} ** 256; // This is bad
        var i_buf: usize = 0;
        var field: u4 = 0; // Max of 10

        for (metadata_section) |c| {
            switch (c) {
                '\r' => continue, // FUCK I HATE THIS SHIT
                '\n' => {
                    if (field != 0) {
                        switch (field) {
                            1 => {
                                self.title = try std_allocator.alloc(u8, i_buf);
                                @memcpy(self.title, buffer[0..i_buf]);
                            },
                            2 => {
                                self.title_unicode = try std_allocator.alloc(u8, i_buf);
                                @memcpy(self.title_unicode, buffer[0..i_buf]);
                            },
                            3 => {
                                self.artist = try std_allocator.alloc(u8, i_buf);
                                @memcpy(self.artist, buffer[0..i_buf]);
                            },
                            4 => {
                                self.artist_unicode = try std_allocator.alloc(u8, i_buf);
                                @memcpy(self.artist_unicode, buffer[0..i_buf]);
                            },
                            5 => {
                                self.creator = try std_allocator.alloc(u8, i_buf);
                                @memcpy(self.creator, buffer[0..i_buf]);
                            },
                            6 => {
                                self.version = try std_allocator.alloc(u8, i_buf);
                                @memcpy(self.version, buffer[0..i_buf]);
                            },
                            7 => {
                                self.source = try std_allocator.alloc(u8, i_buf);
                                @memcpy(self.source, buffer[0..i_buf]);
                            },
                            8 => { // TODO: SEE TAGS FIELD
                                self.tags = try std_allocator.alloc(u8, i_buf);
                                @memcpy(self.tags, buffer[0..i_buf]);
                            },
                            9 => {
                                self.beatmap_id = try std.fmt.parseUnsigned(u32, buffer[0..i_buf], 10);
                            },
                            10 => {
                                self.set_id = try std.fmt.parseInt(i32, buffer[0..i_buf], 10);
                            },
                            else => return MetadataSectionErr.InvalidField,
                        }
                        @memset(&buffer, 0);
                        i_buf = 0;
                        field = 0;
                    }
                },
                ':' => blk: {
                    if (field != 0) {
                        buffer[i_buf] = c; // Make sure to add it to the shit
                        i_buf += 1;
                        break :blk; // As to not fuck up if theres a ':' in any of the data - hopefully this works now
                    }
                    _label: for (SECTION_LABELS) |L| { // Find the field this should go in
                        if (std.ascii.eqlIgnoreCase(L, buffer[0..i_buf])) break :_label;
                        field += 1;
                    }

                    @memset(&buffer, 0);
                    i_buf = 0;
                    break :blk;
                },
                else => {
                    buffer[i_buf] = c;
                    i_buf += 1;
                },
            }
        }
    }

    pub fn deinit(self: *Metadata) void {
        std_allocator.free(self.title);
        std_allocator.free(self.title_unicode);
        std_allocator.free(self.artist);
        std_allocator.free(self.artist_unicode);
        std_allocator.free(self.creator);
        std_allocator.free(self.version);
        std_allocator.free(self.source);
        std_allocator.free(self.tags); // FIXME: idk if this works
    }

    pub fn genBackupVerName(self: *Metadata) ![]u8 {

        // Creating a timestamp
        var tstamp: std.time.epoch.EpochSeconds = undefined;
        tstamp.secs = @as(usize, @intCast(std.time.timestamp()));
        var hms: std.time.epoch.DaySeconds = tstamp.getDaySeconds();
        var day: std.time.epoch.EpochDay = tstamp.getEpochDay();
        const month = day.calculateYearDay().calculateMonthDay().month;
        const year = day.calculateYearDay().year;
        const day_of_month = day.calculateYearDay().calculateMonthDay().day_index;
        const fmtstr = try std.fmt.allocPrint(std_allocator, "{d:0>2}{d:0>2}{d:0>2}{d:0>2}{d:0>2}{d:0>2}", .{ year, month.numeric(), day_of_month, hms.getHoursIntoDay(), hms.getMinutesIntoHour(), hms.getSecondsIntoMinute() });

        return try std.mem.concat(std_allocator, u8, &[_][]u8{ @constCast("b-"), fmtstr, @constCast("-"), self.version });
    }

    pub fn genBackupFileName(self: *Metadata) ![]u8 {
        var l: usize = 0;
        for (self.artist) |c| {
            switch (c) {
                '/' => continue,
                else => l += 1,
            }
        }

        var artist: []u8 = try std_allocator.alloc(u8, l);
        l = 0;
        defer std_allocator.free(artist);

        for (self.artist) |c| {
            switch (c) {
                '/' => continue,
                else => {
                    artist[l] = c;
                    l += 1;
                },
            }
        }

        return try std.mem.concat(std_allocator, u8, &[_][]u8{ artist, @constCast(" - "), self.title, @constCast(" ("), self.creator, @constCast(") ["), try self.genBackupVerName(), @constCast("].osu") }); // Hellfire and brimstone
    }
};
