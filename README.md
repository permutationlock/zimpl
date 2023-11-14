# Zimpl Zig interfaces

A dead simple implementation of [static dispatch][2] interfaces in Zig.
This library is a simplified tiny subset of [ztrait][1].

## What is the idea?

Suppose that we have a generic function to poll for
events in a `Server` struct. The caller passes in a `handler` argument to
provide callbacks for each event.

```Zig
const Serve = struct {
    // ...
    pub fn poll(self: *@This(), handler: anytype) !void {
        try self.pollSockets();
        while (self.getEvent()) |evt| {
            switch (evt) {
                .open => |handle| handler.onOpen(handle),
                .msg => |msg| handler.onMessage(msg.handle, msg.bytes),
                .close => |handle| handler.onClose(handle),
            }
        }
    }
    // ...
};
```

A complaint with the above function is that it is not clear from the
signature, or even the full definition, what the
requirements are for the `handler` argument.

A guaranteed way to make requirements clear is to never rely on duck
typing and have the caller pass in all of the handler callback functions
directly.

```Zig
const Serve = struct {
    // ...
    pub fn poll(
        self: *@This(),
        handler: anytype, 
        comptime onOpen: fn (@TypeOf(handler), Handle) void,
        comptime onMessage: fn (@TypeOf(handler), Handle, Message) void,
        comptime onClose: fn (@TypeOf(handler), Handle) void
    ) void {
        try self.pollSockets();
        while (self.getEvent()) |evt| {
            switch (evt) {
                .open => |handle| onOpen(handler, handle),
                .msg => |msg| onMessage(handler, msg.handle, msg.bytes),
                .close => |handle| onClose(handler, handle),
            }
        }
    }
    // ...
};
```
```Zig
// using the server library
var server = Server{};
var handler = MyHandler{};
try server.listen(port);
while (true) {
    try server.poll(
        &handler,
        MyHandler.onOpen,
        MyHandler.onMessage,
        MyHandler.onClose
    );
}
```


The drawback now is that the function signature is long, and the call
site is verbose as well since each function must be specified.

The idea behind `zimpl` is to try and get the best of both worlds.
Library writers define interfaces and consumers will pass interface
implementations for their types. If a type has
declarations matching the interfaces, the interface implementation
can be inferred.

```Zig
const Serve = struct {
    // ...
    pub fn Handler(comptime Type: type) type {
        return struct {
            pub const onOpen = fn (*Type, Handle) void;
            pub const onMessage = fn (*Type, Handle, []const u8) void;
            pub const onClose = fn (*Type, Handle) void;
        };
    }

    pub fn poll(
        self: *Self,
        handler: anytype,
        handler_impl: Impl(PtrChild(@TypeOf(handler)), Handler)
    ) void {
        try self.pollSockets();
        while (self.getEvent()) |evt| {
            switch (evt) {
                .open => |handle| handler_impl.onOpen(handler, handle),
                .msg => |msg| handler_impl.onMessage(handler, msg.handle, msg.bytes),
                .close => |handle| handler_impl.onClose(handler, handle),
            }
        }
    }
    // ...
};
```
```Zig
// using the server library
var server = Server{};
var handler = MyHandler{};
try server.listen(port);
while (true) {
    try server.poll(&handler, .{});
}
```

For a full discussion on the above example see [this article][5].

## The library

This might sound complicated, but the `zimpl` module is ~50 lines of code
and exposes exactly two declarations.

### `Impl`

```Zig
pub fn Impl(comptime Type: type, comptime Ifc: fn (type) type) type { ... }
```

#### Arguments

There are no special requirements for the arguments of `Impl`.

#### Return value

A call to `Impl(Type, Ifc)` returns a struct type.
For each declaration `Ifc(Type).decl` that is a type,
a field of the same name
`decl` is added to `Impl(Type, Ifc)` with type `Ifc(Type).decl`.

If the declaration `Type.decl` exists and `@TypeOf(Type.decl)`
is `Ifc(Type).decl`,
then `Type.decl` is set as the default value for the field
`decl` in `Impl(Type, Ifc)`.

#### Intent

The `Ifc` parameter is an interface: given
a type `Type`, the namespace of `Ifc(Type)` defines a set of
declarations that must be implemented for `Type`.
The struct type `Impl(Type, Ifc)` represents a specific
implementation of the interface `Ifc` for `Type`.

The struct `Impl(Type, Ifc)` will be
default constructable if `Type` naturally implements the
interface, i.e. if `Type` has declarations matching
`Ifc(Type)`.

```Zig
// An interface
fn Iterator(comptime Type: type) type {
    return struct {
        pub const next = fn (*Type) ?u32;
    };
}

// A generic function using the interface
fn sum(iter: anytype, impl: Impl(@TypeOf(iter), Iterator)) u32 {
    var mut_iter = iter;
    var sum: u32 = 0;
    while (impl.next(&mut_iter)) |n| {
        sum += n;
    }
    return sum;
}

test {
    const SliceIter = struct {
        slice: []const u32,

        pub fn init(s: []const u32) @This() {
            return .{ .slice = s, };
        }

        pub fn next(self: *@This()) ?u32 {
            if (self.slice.len == 0) {
                return null;
            }
            const head = self.slice[0];
            self.slice = self.slice[1..];
            return head;
        }
    };
    const nums = [_]u32{ 1, 2, 3, 4, 5, };
    const total = sum(SliceIter.init(&nums), .{});
    testing.expectEqual(@as(u32, 15), total);
}
```

There is a simlar [full example][4].

### `PtrChild`

```Zig
pub fn PtrChild(comptime Type: type) type { ... }
```

#### Arguments

A compile error is thrown unless `Type` is a single item pointer.

#### Return value

Returns the child type of a single item pointer.

#### Intent

Often one will want to have generic function take a pointer as an `anytype`
argument. Using
`PtrChild` it is simple to specify interface requirements
for the type that the pointer dereferences to.

```Zig
fn Incrementable(comptime Type: type) type {
    return struct {
        pub const increment = fn (*Type) void;
        pub const read = fn (*const Type) usize;
    };
}

// Accepting a pointer with an interface
pub fn countToTen(
    ctr: anytype,
    impl: Impl(PtrChild(@TypeOf(ctr)), Incrementable)
) void {
    while (impl.read(ctr) < 10) {
        impl.increment(ctr);
    }
}

test {
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
```
There is a similar [full example][3].

[1]: https://github.com/permutationlock/ztrait
[2]: https://en.wikipedia.org/wiki/Static_dispatch
[3]: https://github.com/permutationlock/zimpl/blob/main/examples/count.zig
[4]: https://github.com/permutationlock/zimpl/blob/main/examples/iterator.zig
[5]: https://musing.permutationlock.com/posts/blog-working_with_anytype.html
