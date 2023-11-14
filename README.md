# zimpl: Zig interfaces

A dead simple implementation of interfaces based on a tiny subset of
[ztrait][1].  The `zimpl` module currently exposes a two declarations.

## `Impl`

```Zig
pub fn Impl(comptime Type: type, comptime Ifc: fn (type) type) type { ... }
```

### Arguments

There are no requirements on the arguments of `Impl`.

### Return value

A call to `Impl(Type, Ifc)` returns a struct type with one field `d`
of type `Ifc(Type).d` for each declaration `d` of `Ifc(Type)`
such that `@TypeOf(Ifc(Type).d) == type`.

If the declaration `Type.d` exists and `@TypeOf(Type.d) == Ifc(Type).d`,
then `Type.d` is the default value for the field `d` in `Impl(Type, Ifc)`.

### Intent

The idea is that the `Ifc` parameter defines an interface: a set of
declarations that a type must implement. For a given type `T` the
declarations that must be implemented by `T` are exactly the
`type` valued declarations of `Ifc(T)`.

The returned struct type `Impl(Type, Ifc)` represents a specific
implementation of the interface `Ifc` for `Type`. The implementation
struct is defined such that `Impl(Type, Ifc){}` will
default construct so long as `Type` naturally implements the
interface.

## `PtrChild`

```Zig
pub fn PtrChild(comptime Type: type) type { ... }
```

### Arguments

A compile error is thrown unless `Type` is a single item pointer.

### Return value

Returns the child type of a single item pointer.

### Intent

Often a generic function will wish to take a pointer as an `anytype`
argument alongside a corresponding interface implementation. Using
`PtrChild` it is simple to specify this requirement.

```Zig
fn foo(ptr: anytype, Impl(PtrChild(@TypeOf(ptr)), Ifc)) ...
```

## Examples

```Zig
const std = @import("std");
const testing = std.testing;

const zimpl = @import("zimpl");
const Impl = zimpl.Impl;
const PtrChild = zimpl.PtrChild;

fn Incrementable(comptime Type: type) type {
    return struct {
        pub const increment = fn (*Type) void;
        pub const read = fn (*const Type) usize;
    };
}

pub fn countToTen(
    ctr: anytype,
    impl: Impl(PtrChild(@TypeOf(ctr)), Incrementable)
) void {
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
