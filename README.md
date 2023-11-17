# Zimpl Zig interfaces

A dead simple implementation of [static dispatch][2] interfaces in Zig.
This library is a simplified tiny subset of [ztrait][1].

## What is the idea?

Suppose that we have a generic function to poll for
events in a `Server` struct. The caller passes in a `handler` argument to
provide event callbacks.

```Zig
const Server = struct {
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

A complaint with the above implementation is that it is not clear from the
signature, or even the full definition, what the
requirements are for the `handler` argument.

A guaranteed way to make requirements clear is to never rely on duck
typing and have the caller pass in all of the handler callback functions
directly.

```Zig
const Server = struct {
    // ...
    pub fn poll(
        self: *@This(),
        handler: anytype, 
        comptime onOpen: fn (@TypeOf(handler), Handle) void,
        comptime onMessage: fn (@TypeOf(handler), Handle, []const u8) void,
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

The drawback now is that the function signature is long and the call
site is verbose. Additionally, if we ever want to use a `handler`
parameter in another function then set of callback paramemters
would need to be defined again separately.

The idea behind `zimpl` is to try and get the best of both worlds:
 - Library writers define interfaces and require an interface
   implementation to be passed alongside each generic parameter.
 - Library consumers can define interface
   implementations for types, and if a type has matching
   declarations for an interfaces then the implementation
   can be inferred via a default constructor.

```Zig
const Server = struct {
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
    // impl can be default constructed because MyHandler has onOpen, onMessage,
    // and onClose member functions with the correct types
    try server.poll(&handler, .{});
}
```

For a full discussion on the above example see [this article][5].

## The zimpl library

The above might sound complicated, but the `zimpl` module is fewer than
100 lines of code
and exposes exactly three declarations: `Impl`, `PtrChild`, and
`Unwrap`.

### `Impl`

```Zig
pub fn Impl(comptime Type: type, comptime Ifc: fn (type) type) type { ... }
```

#### Arguments

There are no special requirements for the arguments of `Impl`.

#### Return value

The return value is a struct type containing one field
for each declaration of `Ifc(Type)`.

Each declaration of type `type` defines a
declaration that must be implemented for the given type. The
default value is inferred to be the corresponding declaration
of `Type` of the same name if it exists and has the correct type[^1].

Every other declaration is "forwarded," that is, defines a field
with its value set as default value.

#### Example

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

### `PtrChild`

```Zig
pub fn PtrChild(comptime Type: type) type { ... }
```

#### Arguments

A compile error is thrown unless `Type` is a single item pointer.

#### Return value

Returns the child type of a single item pointer.

#### Example

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

### `Unwrap`

```Zig
pub fn Unwrap(comptime Type: type) type { ... }
```

#### Arguments

Works for any type.

#### Return value

Unwraps any number of layers of `*`, `?`, or `!` and returns the
underlying type. E.g. `Unwrap(!*?*u8) = u8`.

#### Example

```Zig
pub fn Reader(comptime Type: type) type {
    return struct {
        pub const read = fn (self: Type, buffer: []u8) anyerror!usize;

        pub inline fn readAll(self: Type, buffer: []u8) anyerror!usize {
            var index: usize = 0;
            while (index < buffer.len) {
                const amt = try Unwrap(Type).read(self, buffer[index..]);
                if (amt == 0) break;
                index += amt;
            }
            return index;
        }
    };
}

pub fn readFromReader(
    rdr_data: anytype,
    comptime rdr_impl: zimpl.Impl(@TypeOf(rdr_data), Reader),
    output: []u8,
) !void {
    const len = try rdr_impl.readAll(rdr_data, output);
    if (len != output.len) {
        return error.EndOfStream;
    }
}

const MyReader = struct {
    buffer: []const u8,
    pos: usize,

    pub fn read(self: *@This(), out_buffer: []u8) anyerror!usize {
        const len = @min(self.buffer[self.pos..].len, out_buffer.len);
        @memcpy(
            out_buffer[0..len],
            self.buffer[self.pos..][0..len],
        );
        self.pos += len;
        return len;
    }
};

test {
    const in_buf: []const u8 = "I really hope that this works!";
    var reader = MyReader{ .buffer = in_buf, .pos = 0 };
    var out_buf: [16]u8 = undefined;
    try readFromReader(&reader, .{}, &out_buf);
    try testing.expectEqualSlices(u8, in_buf[0..out_buf.len], &out_buf);
}
```

[1]: https://github.com/permutationlock/ztrait
[2]: https://en.wikipedia.org/wiki/Static_dispatch
[3]: https://github.com/permutationlock/zimpl/blob/main/examples/count.zig
[4]: https://github.com/permutationlock/zimpl/blob/main/examples/iterator.zig
[5]: https://musing.permutationlock.com/posts/blog-working_with_anytype.html

[^1]: Technically default values are inferred from `Unwrap(Type)`.
    But note that if `Type` has a namespace then `Unwrap(Type)=Type`.
