# Zimpl Zig interfaces

A dead simple implementation of [static dispatch][2] interfaces in Zig
that emerged from a tiny subset of [ztrait][1]. See [here][3]
for some motivation.

The `zimpl` module is ~30 lines of code and exposes one public
declaration: `Impl`.

```Zig
pub fn Impl(comptime Ifc: fn (type) type, comptime T: type) type { ... }
```

## Arguments

The function `Ifc` must always return a struct type. If `Unwrap(T)`
has a declaration matching the name of a field from
`Ifc(T)` that cannot coerce to the type of the field, then a
compile error will occur.

### Unwrap

The internal `Unwrap` function removes all layers of `*`, `?`, or `!`
wrapping a type, e.g. `Unwrap(!?*u32)` is `u32`.

## Return value

The type `Impl(Ifc, T)` is a struct type with the same fields
as `Ifc(T)`, but with the default value of each field set equal to
the declaration of `Unwrap(T)` of the same name, if such a declaration
exists.

## Example

```Zig
// An interface
pub fn Reader(comptime T: type) type {
    return struct {
        ReadError: type = error{},
        read: fn (reader_ctx: T, buffer: []u8) anyerror!usize,
    };
}

// A collection of functions using the interface
pub const io = struct {
    pub inline fn read(
        reader_ctx: anytype,
        reader_impl: Impl(Reader, @TypeOf(reader_ctx)),
        buffer: []u8,
    ) reader_impl.ReadError!usize {
        return @errorCast(reader_impl.read(reader_ctx, buffer));
    }

    pub inline fn readAll(
        reader_ctx: anytype,
        reader_impl: Impl(Reader, @TypeOf(reader_ctx)),
        buffer: []u8,
    ) reader_impl.ReadError!usize {
        return readAtLeast(reader_ctx, reader_impl, buffer, buffer.len);
    }

    pub inline fn readAtLeast(
        reader_ctx: anytype,
        reader_impl: Impl(Reader, @TypeOf(reader_ctx)),
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

test "define and use a reader" {
    const FixedBufferReader = struct {
        buffer: []const u8,
        pos: usize = 0,

        pub fn read(self: *@This(), out_buffer: []u8) error{}!usize {
            const len = @min(self.buffer[self.pos..].len, out_buffer.len);
            @memcpy(out_buffer[0..len], self.buffer[self.pos..][0..len]);
            self.pos += len;
            return len;
        }
    };
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

test "use std.os.fd_t as a reader via an explicitly defined interface" {
    var buffer: [19]u8 = undefined;
    const fd = try std.os.open("my_file.txt", std.os.O.RDONLY, 0);
    try io.readAll(
        fd,
        .{ .read = std.os.read, .ReadError = std.os.ReadError, },
        &buffer,
    );

    try std.testing.expectEqualStrings("Hello, I am a file!", &buffer);
}
```

More in-depth [examples][4] are provided.

[1]: https://github.com/permutationlock/ztrait
[2]: https://en.wikipedia.org/wiki/Static_dispatch
[3]: https://github.com/permutationlock/zimpl/blob/main/why.md
[4]: https://github.com/permutationlock/zimpl/blob/main/examples
