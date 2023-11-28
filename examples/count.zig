const std = @import("std");
const testing = std.testing;

const Impl = @import("zimpl").Impl;

fn Counter(comptime T: type) type {
    return struct {
        increment: fn (T) void,
        read: fn (T) usize,
    };
}

pub fn countToTen(
    ctr_ctx: anytype,
    ctr_impl: Impl(Counter, @TypeOf(ctr_ctx)),
) void {
    while (ctr_impl.read(ctr_ctx) < 10) {
        ctr_impl.increment(ctr_ctx);
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
    countToTen(&count, .{ .increment = USize.inc, .read = USize.deref });
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
    var counter: MyCounter = .{ .count = 0 };
    countToTen(&counter, .{});
    try testing.expectEqual(@as(usize, 10), counter.count);
}

fn otherInc(self: *MyCounter) void {
    self.count = 1 + self.count * 2;
}

test "override implementation" {
    var counter: MyCounter = .{ .count = 0 };
    countToTen(&counter, .{ .increment = otherInc });
    try testing.expectEqual(@as(usize, 15), counter.count);
}
