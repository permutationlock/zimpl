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
parameter in another function then set of callback parameters
would need to be defined again separately.

The idea behind `zimpl` is to try and get the best of both worlds:
 - Library writers define interfaces and require an interface
   implementation to be passed alongside each generic parameter.
 - Library consumers must define interface
   implementations, but if a type has declarations matching
   an interface then the implementation
   can be inferred via a default constructor.

```Zig
const Server = struct {
    // ...
    pub fn Handler(comptime Type: type) type {
        return struct {
            pub const onOpen = fn (Type, Handle) void;
            pub const onMessage = fn (Type, Handle, []const u8) void;
            pub const onClose = fn (Type, Handle) void;
        };
    }

    pub fn poll(
        self: *Self,
        handler_ctx: anytype,
        handler_impl: Impl(@TypeOf(handler_ctx), Handler)
    ) void {
        try self.pollSockets();
        while (self.getEvent()) |evt| {
            switch (evt) {
                .open => |handle| handler_impl.onOpen(handler_ctx, handle),
                .msg => |msg| handler_impl.onMessage(
                    handler_ctx,
                    msg.handle,
                    msg.bytes,
                ),
                .close => |handle| handler_impl.onClose(handler_ctx, handle),
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

## The Zimpl library

The above might sound complicated, but the `zimpl` module is around
100 lines of code
and exposes exactly three declarations: `Impl`, `PtrChild`, and
`Unwrap`.

### `Impl`

```Zig
pub fn Impl(comptime Type: type, comptime Ifc: anytype) type { ... }
```

#### Arguments

The `Ifc` parameter must either be of type `fn (type) type`
or be a tuple where each field has type `fn (type) type`. Moreover,
all types produced by such functions must be struct types
containing only declarations of type `type`.

#### Return value

The return value is a struct type containing one field
for each type valued declaration of `Ifc(Type)`[^2].
The default value of each field is set to be the
declaration
of `Type` of the same name, if such a declaration exists
with a matching type[^1].

If `Ifc(Type)` contains declarations that aren't types, then a compile
error is produced.

#### Example

```Zig
// An interface
pub fn Reader(comptime Type: type) type {
    return struct {
        pub const ReadError = type;
        pub const read = fn (reader_ctx: Type, buffer: []u8) anyerror!usize;
    };
}

// A collection of functions using the interface
pub const IO = struct {
    pub inline fn read(
        reader_ctx: anytype,
        reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        buffer: []u8,
    ) reader_impl.ReadError!usize {
        return @errorCast(reader_impl.read(
            reader_ctx,
            buffer,
        ));
    }

    pub inline fn readAll(
        reader_ctx: anytype,
        reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        buffer: []u8,
    ) reader_impl.ReadError!usize {
        return readAtLeast(reader_ctx, reader_impl, buffer, buffer.len);
    }

    pub inline fn readAtLeast(
        reader_ctx: anytype,
        reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        buffer: []u8,
        len: usize,
    ) reader_impl.ReadError!usize {
        assert(len <= buffer.len);
        var index: usize = 0;
        while (index < len) {
            const amt = try read(reader_ctx, reader_impl, buffer[index..]);
            if (amt == 0) break;
            index += amt;
        }
        return index;
    }
};

// A type satisfying the Reader interface
const MyReader = struct {
    buffer: []const u8,
    pos: usize,

    pub const ReadError = error{};

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
    const len = try IO.readAll(&reader, .{}, &out_buf);

    try testing.expectEqualSlices(u8, in_buf[0..len], out_buf[0..len]);
}
```
A more complete Zimpl implementation of the interfaces in
`std.io` is provided in [examples/io.zig][6].

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

[1]: https://github.com/permutationlock/ztrait
[2]: https://en.wikipedia.org/wiki/Static_dispatch
[3]: https://github.com/permutationlock/zimpl/blob/main/examples/count.zig
[4]: https://github.com/permutationlock/zimpl/blob/main/examples/iterator.zig
[5]: https://musing.permutationlock.com/posts/blog-working_with_anytype.html
[6]: https://github.com/permutationlock/zimpl/blob/main/examples/io.zig

[^1]: Technically default values are inferred from `Unwrap(Type)`.
    But note that if `Type` has a namespace then `Unwrap(Type)=Type`.
[^2]: If `Ifc` is a tuple of functions `.{ Ifc1, Ifc2, ..., IfcN }`, then
    `Ifc(Type)` is instead constructed to as shown below below.
    ```Zig
    Ifc(Type) = struct {
        pub usingnamespace Ifc1(Type);
        pub usingnamespace Ifc2(Type);
        ...
        pub usingnamespace IfcN(Type);
    };
    ```
