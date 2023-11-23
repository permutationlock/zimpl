# Why Zimpl?

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

A big drawback now is that the function signature is long and the call
site is verbose. Additionally, if we ever want to use a `handler`
parameter in another function then the callback parameters
would need to be defined again separately.

The logical next step would be to create a struct type to hold all of
the callback functions.

```Zig
const Server = struct {
    // ...
    pub fn Handler(comptime Type: type) type {
        return struct {
            onOpen: fn (Type, Handle) void,
            onMessage: fn (Type, Handle, []const u8) void,
            onClose: fn (Type, Handle) void,
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

Unfortunately, calling `poll` is
still needlessly verbose when the type already has the corresponding
callbacks as member functions.

The Zimpl library provides the `Impl` function that will infer the default
value for each member of `Handler(Type)` from the declarations of `Type`.

```Zig
const Server = struct {
    // ...
    pub fn poll(
        self: *Self,
        handler_ctx: anytype,
        handler_impl: Impl(@TypeOf(handler_ctx), Handler)
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
```
```Zig
// using the server library
var server = Server{};
var handler = MyHandler{};
try server.listen(8080);
while (true) {
    // Impl(*MyHandler, Handler) can be default constructed because MyHandler
    // has onOpen, onMessage, and onClose member functions
    try server.poll(&handler, .{});
}
```

For a longer discussion on the above example see [this article][1].
Go to the [Zimpl][2] page for more examples.

[1]: https://musing.permutationlock.com/posts/blog-working_with_anytype.html
[2]: https://github.com/permutationlock/zimpl
