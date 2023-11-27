# Zimpl Zig interfaces

A dead simple implementation of [static dispatch][2] interfaces in Zig
that emerged from a tiny subset of [ztrait][1]. See [here][3]
for some motivation.

The `zimpl` module is <10 lines of code and exposes one public
declaration `Unwrap` that removes all layers of `*`, `?`, and `!`
wrapping a type.

```Zig
pub fn Unwrap(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .Pointer => |info| if (info.size == .One) Unwrap(info.child) else T,
        .Optional => |info| Unwrap(info.child),
        .ErrorUnion => |info| Unwrap(info.payload),
        else => T,
    };
}
```

## Why Zimpl?

Suppose that we have a function to poll for events in a `Server` struct
that manages TCP connections.
The caller passes in a generic `handler` argument
to provide event callbacks.

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
```Zig
// using the server library
var server = Server{};
var handler = MyHandler{};
try server.listen(8080);
while (true) {
    try server.poll(&handler);
}
```

A complaint with the above implementation is that it is not clear from the
function signature of `poll`, or even the full implementation, what the
exact requirements are for the `handler` argument.

A guaranteed way to make requirements clear is to never rely on duck
typing and have the caller pass in the handler callback functions
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
try server.listen(8080);
while (true) {
    try server.poll(
        &handler,
        MyHandler.onOpen,
        MyHandler.onMessage,
        MyHandler.onClose
    );
}
```

Unfortunately, now the function signature is long and the call
site is verbose. Additionally, if we need to take a `handler`
somewhere else, then the callback parameters
will need to be defined again separately.

The logical next step would be to create a struct type to hold all of
the callback functions.

```Zig
const Server = struct {
    // ...
    pub fn Handler(comptime T: type) type {
        return struct {
            onOpen: fn (T, Handle) void,
            onMessage: fn (T, Handle, []const u8) void,
            onClose: fn (T, Handle) void,
        };
    }

    pub fn poll(
        self: *Self,
        handler_ctx: anytype,
        handler_impl: Handler(@TypeOf(handler_ctx)),
    ) void {
        try self.pollSockets();
        while (self.getEvent()) |evt| {
            switch (evt) {
                .open => |handle| handler_impl.onOpen(handler_ctx, handle),
                .msg => |msg| handler_impl.onMessage(handler_ctx, msg.handle, msg.bytes),
                .close => |handle| handler_impl.onClose(handler_ctx, handle),
            }
        }
    }
    // ...
};
```

This cleaned up the function signature, but calling `poll` is still
needlessly verbose when the type already
has valid callback member functions.

```Zig
// using the server library
var server = Server{};
var handler = MyHandler{};
try server.listen(8080);
while (true) {
    try server.poll(&handler, .{
        .onOpen = MyHandler.onOpen,
        .onMessage = MyHandler.onMessage,
        .onClose = MyHandler.onClose,
    });
}
```

The Zimpl library provides the function `Unwrap` removes layers of `*`, `?`,
and `!` wrapping a type. We can use this to set the default values
for the callback funtions of `Handler(T)` equal to the corresponding
declarations of `Unwrap(T)`.

```Zig
const Server = struct {
    // ...
    pub fn Handler(comptime T: type) type {
        return struct {
            onOpen: fn (T, Handle) void = Unwrap(T).onOpen,
            onMessage: fn (T, Handle, []const u8) void = Unwrap(T).onMessage,
            onClose: fn (T, Handle) void = Unwrap(T).onClose,
        };
    }
    // ...
```
```Zig
// using the server library
var server = Server{};
var handler = MyHandler{};
try server.listen(8080);
while (true) {
    // Handler(*MyHandler) can be default constructed because
    // Unwrap(*MyHandler) = MyHandler which has onOpen, onMessage,
    // and onClose member functions
    try server.poll(&handler, .{});
}
```

For a longer discussion on the above example see [this article][5].

## A std.io example

```Zig
// An interface
pub fn Reader(comptime T: type) type {
    return struct {
        ReadError: type = Unwrap(T).ReadError,
        read: fn (reader_ctx: T, buffer: []u8) anyerror!usize = Unwrap(T).read,
    };
}

// A collection of functions using the interface
pub const io = struct {
    pub inline fn read(
        reader_ctx: anytype,
        reader_impl: Reader(@TypeOf(reader_ctx)),
        buffer: []u8,
    ) reader_impl.ReadError!usize {
        return @errorCast(reader_impl.read(reader_ctx, buffer));
    }

    pub inline fn readAll(
        reader_ctx: anytype,
        reader_impl: Reader(@TypeOf(reader_ctx)),
        buffer: []u8,
    ) reader_impl.ReadError!usize {
        return readAtLeast(reader_ctx, reader_impl, buffer, buffer.len);
    }

    pub inline fn readAtLeast(
        reader_ctx: anytype,
        reader_impl: Reader(@TypeOf(reader_ctx)),
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

// A type satisfying the Reader interface (uses default ReadError)
const FixedBufferReader = struct {
    buffer: []const u8,
    pos: usize = 0,

    pub const ReadError = error{};

    pub fn read(self: *@This(), out_buffer: []u8) ReadError!usize {
        const len = @min(self.buffer[self.pos..].len, out_buffer.len);
        @memcpy(out_buffer[0..len], self.buffer[self.pos..][0..len]);
        self.pos += len;
        return len;
    }
};

test "use FixedBufferReader as a reader" {
    const in_buf: []const u8 = "I really hope that this works!";
    var reader = FixedBufferReader{ .buffer = in_buf };

    var out_buf: [16]u8 = undefined;
    const len = try io.readAll(&reader, .{}, &out_buf);

    try testing.expectEqualStrings(in_buf[0..len], out_buf[0..len]);
}

test "use std.fs.File as a reader" {
    var buffer: [19]u8 = undefined;
    var file = try std.fs.cwd().openFile("my_file.txt", .{});
    try io.readAll(file, .{}, &buffer);

    try std.testing.expectEqualStrings("Hello, I am a file!", &buffer);
}
```

More in-depth [examples][4] are provided.

[1]: https://github.com/permutationlock/ztrait
[2]: https://en.wikipedia.org/wiki/Static_dispatch
[3]: https://github.com/permutationlock/zimpl/blob/main/why.md
[4]: https://github.com/permutationlock/zimpl/blob/main/examples
[5]: https://musing.permutationlock.com/posts/blog-working_with_anytype.html
