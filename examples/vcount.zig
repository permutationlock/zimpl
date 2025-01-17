const std = @import("std");
const testing = std.testing;

const ztable = @import("zimpl").ztable;
const VIfc = ztable.VIfc;

const Counter = VIfc(@import("count.zig").Counter);

pub fn countToTen(ctr: Counter) void {
    while (ctr.vtable.read(ctr.ctx) < 10) {
        ctr.vtable.increment(ctr.ctx);
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
    countToTen(Counter.init(
        .direct,
        &count,
        .{ .increment = USize.inc, .read = USize.deref },
    ));
    try testing.expectEqual(@as(usize, 10), count);
}

const MyCounter = struct {
    count: usize,

    pub fn increment(self: *@This()) void {
        self.count += 1;
    }

    pub fn read(self: *const @This()) u32 {
        return self.count;
    }
};

test "infer implementation" {
    var my_counter: MyCounter = .{ .count = 0 };
    countToTen(Counter.init(.direct, &my_counter, .{}));
    try testing.expectEqual(@as(usize, 10), my_counter.count);
}

fn otherInc(self: *MyCounter) void {
    self.count = 1 + self.count * 2;
}

test "override implementation" {
    var my_counter: MyCounter = .{ .count = 0 };
    countToTen(Counter.init(
        .direct,
        &my_counter,
        .{ .increment = otherInc },
    ));
    try testing.expectEqual(@as(usize, 15), my_counter.count);
}
