# zimpl: Zig interfaces

A dead simple implementation of interfaces based on a tiny subset of
[ztrait][1].  The `zimpl` module currently exposes a single declaration.

```Zig
pub fn Impl(comptime Type: type, comptime Ifc: fn (type) type) type { ... }
```

### Arguments

There are no requirements on the arguments of `Impl`.

### Return value

Let `T: type` and `I: fn (type) type`. Define `U = Unwrap(T)` where
`Unwrap` is as defined below.

```Zig
fn Unwrap(comptime Type: type) type {
    return switch (@typeInfo(Type)) {
        .Pointer => |info| if (info.size == .One) info.child else Type,
        else => Type,
    };
}
```

A call to `Impl(T, I)` returns a struct type with one field `d`
for each declaration `I(U).d` where `@TypeOf(I(U).d) == type`. If the
declaration `U.d` exists and `@TypeOf(U.d) == I(U).d`, then `U.d` is
the default value for the field `d` in `Impl(T, I)`.

## Intent

The idea is that the `Ifc` parameter defines an interface: a set of
declarations that a type must implement. For a given type `T` the
declarations that must be implemented by `T` are exactly the
`type` valued declarations of `Ifc(T)`.

The returned struct type `Impl(Type, Ifc)` represents a specific
implementation of the interface `Ifc` for `Unwrap(Type)`. The struct
is defined such that `Impl(Type, Ifc){}` will
default construct so long as `Unwrap(Type)` naturally implements the
interface, i.e. `Unwrap(Type)` has a matching declaration for
each type valued declaration of `Ifc(Unwrap(Type))`.

Single pointers are unwrapped with `Unwrap` to mimic the way that Zig's syntax
automatically unwraps single item pointers to call member functions.
E.g. if `t` is of type `*T` then `t.f()` is evaluated as `T.f(t)`.

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

```

[1]: https://github.com/permutationlock/ztrait
