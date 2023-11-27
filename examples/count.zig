const std = @import("std");
const testing = std.testing;

const Unwrap = @import("zimpl").Unwrap;

fn Counter(comptime T: type) type {
    return struct {
        increment: fn (T) void = Unwrap(T).increment,
        read: fn (T) usize = Unwrap(T).read,
    };
}

pub fn countToTen(
    ctr_ctx: anytype,
    comptime ctr_impl: Counter(@TypeOf(ctr_ctx)),
) void {
    while (ctr_impl.read(ctr_ctx) < 10) {
        ctr_impl.increment(ctr_ctx);
    }
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
