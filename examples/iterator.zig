const std = @import("std");
const testing = std.testing;

const Impl = @import("zimpl").Impl;

fn Iterator(comptime Data: type) fn (type) type {
    return struct {
        pub fn Ifc(comptime T: type) type {
            return struct {
                next: fn (*T) ?*Data,
            };
        }
    }.Ifc;
}

pub fn apply(
    comptime T: type,
    comptime f: fn (*T) void,
    iter: anytype,
    impl: Impl(Iterator(T), @TypeOf(iter)),
) void {
    var mut_iter = iter;
    while (impl.next(&mut_iter)) |t| {
        f(t);
    }
}

fn addThree(n: *i32) void {
    n.* += 3;
}

fn SliceIter(comptime T: type) type {
    return struct {
        slice: []T,

        pub fn init(s: []T) @This() {
            return .{
                .slice = s,
            };
        }

        pub fn next(self: *@This()) ?*T {
            if (self.slice.len == 0) {
                return null;
            }
            const head = &self.slice[0];
            self.slice = self.slice[1..];
            return head;
        }
    };
}

test "slice iterator" {
    var fibo = [_]i32{ 1, 1, 2, 3, 5, 8, 13, 21 };
    apply(i32, addThree, SliceIter(i32).init(&fibo), .{});
    try testing.expectEqualSlices(
        i32,
        &[_]i32{ 4, 4, 5, 6, 8, 11, 16, 24 },
        &fibo,
    );
}
