# Zimpl Zig interfaces

A dead simple implementation of [static dispatch][2] interfaces in Zig.
This library is a simplified tiny subset of [ztrait][1].

The `zimpl` module currently exposes a two declarations.

## `Impl`

```Zig
pub fn Impl(comptime Type: type, comptime Ifc: fn (type) type) type { ... }
```

### Arguments

There are no special requirements for the arguments of `Impl`.

### Return value

A call to `Impl(Type, Ifc)` returns a `comptime` generated struct type.
For each declaration `d` of `Ifc(Type)` such that
`@TypeOf(Ifc(Type).d) == type`, a field `d` of the same name is added to
`Impl(Type, Ifc)` of type `Ifc(Type).d`.

If the declaration `Type.d` exists and `@TypeOf(Type.d) == Ifc(Type).d`,
then `Type.d` is set to be the default value for the field `d` in
`Impl(Type, Ifc)`.

### Intent

The idea is that the `Ifc` parameter is an interface: given
a type `Type`, the struct `Ifc(Type)` defines a set of declarations
that must be implemented for `Type`.
The returned struct type `Impl(Type, Ifc)` represents a specific
implementation of the interface `Ifc` for `Type`.

Note from return value definition above
that the struct `Impl(Type, Ifc)` will be
default constructable if `Type` naturally implements the
interface, i.e. if `Type` has declarations matching
`Ifc(Type)`.

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
argument alongside an interface implementation. Using
`PtrChild` it is simple to specify that the interface requirement is
for the type that the pointer dereferences to.

```Zig
fn foo(ptr: anytype, Impl(PtrChild(@TypeOf(ptr)), Ifc)) ...
```

## Example

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
[2]: https://en.wikipedia.org/wiki/Static_dispatch
