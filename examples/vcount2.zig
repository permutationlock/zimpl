const std = @import("std");
const testing = std.testing;

const ztable = @import("zimpl").ztable;
const VTable = ztable.VTable;
const vtable = ztable.vtable;

const Counter = @import("count.zig").Counter;

pub fn countToTen(ctr_ctx: *anyopaque, ctr_vtable: VTable(Counter)) void {
    while (ctr_vtable.read(ctr_ctx) < 10) {
        ctr_vtable.increment(ctr_ctx);
    }
}

test "explicit implementation" {
    const USize = struct {
        pub fn inc(i: *usize) void {
            i.* += 1;
        }
        pub fn deref(i: *const usize) usize {
            return i.*;
        }
    };
    var count: usize = 0;
    countToTen(&count, vtable(
        Counter,
        .direct,
        @TypeOf(&count),
        .{ .increment = USize.inc, .read = USize.deref },
    ));
    try testing.expectEqual(@as(usize, 10), count);
}

const MyCounter = struct {
    count: usize,

    pub fn increment(self: *@This()) void {
        self.count += 1;
    }

    pub fn read(self: *const @This()) usize {
        return self.count;
    }
};

test "infer implementation" {
    var my_counter: MyCounter = .{ .count = 0 };
    countToTen(
        &my_counter,
        vtable(Counter, .direct, @TypeOf(&my_counter), .{}),
    );
    try testing.expectEqual(@as(usize, 10), my_counter.count);
}

fn otherInc(self: *MyCounter) void {
    self.count = 1 + self.count * 2;
}

test "override implementation" {
    var my_counter: MyCounter = .{ .count = 0 };
    countToTen(&my_counter, vtable(
        Counter,
        .direct,
        @TypeOf(&my_counter),
        .{ .increment = otherInc },
    ));
    try testing.expectEqual(@as(usize, 15), my_counter.count);
}
