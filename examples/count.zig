const std = @import("std");
const testing = std.testing;

const zimpl = @import("zimpl");
const Impl = zimpl.Impl;
const Interface = zimpl.Interface;
const PtrChild = zimpl.PtrChild;

fn Incrementable(comptime Type: type) Interface {
    return .{
        .requires = struct {
            pub const increment = fn (*Type) void;
            pub const read = fn (*const Type) usize;
        },
    };
}

pub fn countToTen(
    ctr_ptr: anytype,
    comptime ctr_impl: Impl(PtrChild(@TypeOf(ctr_ptr)), Incrementable)
) void {
    while (ctr_impl.read(ctr_ptr) < 10) {
        ctr_impl.increment(ctr_ptr);
    }
}

test "explicit implementation" {
    const USize = struct {
        pub fn inc(i: *usize) void { i.* += 1; }
        pub fn deref(i: *const usize) usize { return i.*; }
    };
    var count: usize = 0;
    countToTen(&count, .{ .increment = USize.inc, .read = USize.deref });
    try testing.expectEqual(@as(usize, 10), count); 
}

test "infer implementation" {
    const MyCounter = struct {
        count: usize,

        pub fn increment(self: *@This()) void {
            self.count += 1;
        }
     
        pub fn read(self: *const @This()) usize {
            return self.count;
        }
    };
    var counter: MyCounter = .{ .count = 0 };
    countToTen(&counter, .{});
    try testing.expectEqual(@as(usize, 10), counter.count);
}

test "override implementation" {
    const MyCounter = struct {
        count: usize,

        pub fn increment(self: *@This()) void {
            self.count += 1;
        }
     
        pub fn read(self: *const @This()) usize {
            return self.count;
        }
    };

    const S = struct {
        pub fn incThree(self: *MyCounter) void {
            self.count = 1 + self.count * 2;
        }
    };
    var counter: MyCounter = .{ .count = 0 };
    countToTen(&counter, .{ .increment = S.incThree });
    try testing.expectEqual(@as(usize, 15), counter.count);
}

