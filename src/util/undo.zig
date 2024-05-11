const std = @import("std");
const sv = @import("../core/sv.zig");
const hit_obj = @import("../core/hitobj.zig");

const UNDO_STACK_LIMIT = 128;
var UNDO_STACK_HGT: usize = 0;

pub const UndoError = error{
    EndOfStack,
};

pub const UndoNode = struct {
    /// Extents of the section to replace: {where to start, where to pick up from}
    extents: [2]i32,

    // TODO: Make this better because this system sucks
    /// Enum to determine the type of the contents
    cont_t: enum {
        HitObj,
        TimePoint,
    },

    /// Whatever existed before the change happened

    // To save myself from type casting horribleness and to speed up testing...
    // we're doing this for now
    tp: []sv.TimingPoint,
    hobj: []hit_obj.HitObject,

    //cont: union {
    //    hobj: []hit_obj.HitObject, // Access as a hit object
    //    tp: []sv.TimingPoint, // Or as a timing point
    //},
    //cont: *anyopaque,

    /// The previous entry in the stack
    prev: ?*UndoNode,

    /// This will allow me to link any related changes (e.g. edit to both hit objects and timing points)
    // Probably not a good way to do this...
    linked: ?*UndoNode,

    pub fn init(self: *UndoNode, start: i32, end: i32, cont: anytype) !void {
        self.linked = null;

        self.extents = [_]i32{ start, end };

        switch (@TypeOf(cont)) { // Switch off type of input
            []hit_obj.HitObject => {
                self.cont_t = .HitObj; // I really don't want to have to deal with *anyopaque and then having to do some nasty casting every time i want to use it
                //self.cont = @ptrCast(try std.heap.page_allocator.alloc(hit_obj.HitObject, cont.len));
                //@memcpy(self.cont, @as(*anyopaque, @ptrCast(&cont)));
                self.hobj = try std.heap.page_allocator.alloc(hit_obj.HitObject, cont.len);
                @memcpy(self.hobj, cont);
            },
            []sv.TimingPoint => {
                self.cont_t = .TimePoint;
                //self.cont = @ptrCast(try std.heap.page_allocator.alloc(sv.TimingPoint, cont.len));
                //@memcpy(self.cont, @as(*anyopaque, @ptrCast(&cont)));
                self.tp = try std.heap.page_allocator.alloc(sv.TimingPoint, cont.len);
                @memcpy(self.tp, cont);
            },
            else => unreachable,
        }
    }

    pub fn deinit(self: *UndoNode) void {
        var current_node: ?*UndoNode = self;
        // Loop through all the linked nodes and free all their contents
        while (current_node.*.linked != null) {
            std.heap.page_allocator.free(current_node.?.*.cont); // Should never fail
            current_node = current_node.?.*.linked;
        }
    }

    pub fn getLastLink(self: *UndoNode) *UndoNode {
        var current_node = self;
        while (current_node.*.linked != null) current_node = current_node.*.linked;
        return current_node;
    }
};

// This will just be the SP... No need for a BP since it just bottoms out at null
pub var UNDO_HEAD: ?*UndoNode = null;

pub fn push(node: *UndoNode) void {
    node.prev = UNDO_HEAD;
    UNDO_HEAD = node;
    UNDO_STACK_HGT += 1;
    if (UNDO_STACK_HGT >= UNDO_STACK_LIMIT) {
        // Remove bottom most element
        // Free bottom most element
        // Point second bottom most element to NULL
    }
}

pub fn pop() !*UndoNode {
    if (UNDO_HEAD) |head| {
        const t: *UndoNode = head;
        UNDO_HEAD = head.prev;
        UNDO_STACK_HGT -= 1;
        return t;
    } else return UndoError.EndOfStack;
}
