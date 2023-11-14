# zimpl: Zig interfaces

A dead simple implementation of interfaces based on a tiny subset of
[ztrait][1].  The `zimpl` module currently exposes a single declaration.

```Zig
pub fn Impl(comptime Type: type, comptime Ifc: fn (type) type) type { ... }
```

### Arguments

There are no requirements on the arguments of `Impl`.

### Return value

A call to `Impl(T, F)` returns a struct type with one field `d`
for each declaration `F(T).d` where `@TypeOf(F(T).d) == type`. If the
declaration `T.d` exists and `@TypeOf(T.d) == F(T).d`, then `T.d` is
the default value for the field `d` in `Impl(T, F)`.

There is a special case when `T = *U` is a single item pointer type.
The `Impl` function first "unwraps" `*U`
to `U`, so `Impl(*U, F)` is equivalent to `Impl(U, F)`. Only one
"layer" is unwrapped, so `**U` will not unwrap to `U`.

The reason for unwrapping single pointers is mimic the way that Zig's syntax
automatically unwraps single item pointers to call member functions. E.g. 
if `u` is of type `*U` then `u.f()` is evaluated as
`@TypeOf(u).Pointer.child.f(u)`.

## Example

```Zig
const std = @import("std");
const testing = std.testing;

const Impl = @import("zimpl").Impl;

fn Incrementable(comptime Type: type) type {
    return struct {
        pub const increment = fn (*Type) void;
        pub const read = fn (*const Type) usize;
    };
}

pub fn countToTen(ctr: anytype, impl: Impl(@TypeOf(ctr), Incrementable)) void {
    while (impl.read(ctr) < 10) {
        impl.increment(ctr);
    }
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

test "explicit implementation" {
    const USize = struct {
        pub fn inc(i: *usize) void { i.* += 1; }
        pub fn deref(i: *const usize) usize { return i.*; }
    };
    var count: usize = 0;
    countToTen(&count, .{ .increment = USize.inc, .read = USize.deref });
    try testing.expectEqual(@as(usize, 10), count); 
}
```

[1]: https://github.com/permutationlock/ztrait
