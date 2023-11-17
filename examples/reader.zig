const std = @import("std");
const testing = std.testing;
const native_endian = @import("builtin").target.cpu.arch.endian();
const mem = std.mem;
const assert = std.debug.assert;

const zimpl = @import("zimpl");
const Impl = zimpl.Impl;

pub fn Reader(comptime Type: type) type {
    return struct {
        pub const ReadError = type;
        pub const read = fn (reader_ctx: Type, buffer: []u8) anyerror!usize;
    };
}

pub const IO = struct {
    pub inline fn read(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        buffer: []u8,
    ) reader_impl.ReadError!usize {
        return @errorCast(reader_impl.read(
            reader_ctx,
            buffer,
        ));
    }

    pub inline fn readAll(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        buffer: []u8,
    ) reader_impl.ReadError!usize {
        return readAtLeast(reader_ctx, reader_impl, buffer, buffer.len);
    }

    pub inline fn readAtLeast(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
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

    pub inline fn readNoEof(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        buf: []u8,
    ) (reader_impl.ReadError || error{EndOfStream})!void {
        const amt_read = try readAll(reader_ctx, buf);
        if (amt_read < buf.len) return error.EndOfStream;
    }

    pub inline fn readAllArrayList(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        array_list: *std.ArrayList(u8),
        max_append_size: usize,
    ) (reader_impl.ReadError || error{ EndOfStream, StreamTooLong })!void {
        return readAllArrayListAligned(
            reader_ctx,
            null,
            array_list,
            max_append_size,
        );
    }

    pub inline fn readAllArrayListAligned(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        comptime alignment: ?u29,
        array_list: *std.ArrayListAligned(u8, alignment),
        max_append_size: usize,
    ) (reader_impl.ReadError || error{StreamTooLong})!void {
        try array_list.ensureTotalCapacity(@min(max_append_size, 4096));
        const original_len = array_list.items.len;
        var start_index: usize = original_len;
        while (true) {
            array_list.expandToCapacity();
            const dest_slice = array_list.items[start_index..];
            const bytes_read = try readAll(reader_ctx, dest_slice);
            start_index += bytes_read;

            if (start_index - original_len > max_append_size) {
                array_list.shrinkAndFree(original_len + max_append_size);
                return error.StreamTooLong;
            }

            if (bytes_read != dest_slice.len) {
                array_list.shrinkAndFree(start_index);
                return;
            }

            try array_list.ensureTotalCapacity(start_index + 1);
        }
    }

    pub inline fn readAllAlloc(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        allocator: mem.Allocator,
        max_size: usize,
    ) (reader_impl.ReadError || error{StreamTooLong})![]u8 {
        var array_list = std.ArrayList(u8).init(allocator);
        defer array_list.deinit();
        try readAllArrayList(reader_ctx, &array_list, max_size);
        return try array_list.toOwnedSlice();
    }

    pub inline fn readUntilDelimiterArrayList(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        array_list: *std.ArrayList(u8),
        delimiter: u8,
        max_size: usize,
    ) (reader_impl.ReadError || error{ EndOfStream, StreamTooLong })!void {
        array_list.shrinkRetainingCapacity(0);
        try streamUntilDelimiter(
            reader_ctx,
            array_list.writer(),
            delimiter,
            max_size,
        );
    }

    pub inline fn readUntilDelimiterAlloc(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        allocator: mem.Allocator,
        delimiter: u8,
        max_size: usize,
    ) (reader_impl.ReadError || error{EndOfStream})![]u8 {
        var array_list = std.ArrayList(u8).init(allocator);
        defer array_list.deinit();
        try streamUntilDelimiter(
            reader_ctx,
            array_list.writer(),
            delimiter,
            max_size,
        );
        return try array_list.toOwnedSlice();
    }

    pub inline fn readUntilDelimiter(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        buf: []u8,
        delimiter: u8,
    ) (reader_impl.ReadError || error{ EndOfStream, StreamTooLong })![]u8 {
        var fbs = std.io.fixedBufferStream(buf);
        try streamUntilDelimiter(
            reader_ctx,
            fbs.writer(),
            delimiter,
            fbs.buffer.len,
        );
        const output = fbs.getWritten();
        buf[output.len] = delimiter; // emulating old behaviour
        return output;
    }

    pub inline fn readUntilDelimiterOrEofAlloc(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        allocator: mem.Allocator,
        delimiter: u8,
        max_size: usize,
    ) (reader_impl.ReadError || error{StreamTooLong})!?[]u8 {
        var array_list = std.ArrayList(u8).init(allocator);
        defer array_list.deinit();
        streamUntilDelimiter(
            reader_ctx,
            array_list.writer(),
            delimiter,
            max_size,
        ) catch |err| switch (err) {
            error.EndOfStream => if (array_list.items.len == 0) {
                return null;
            },
            else => |e| return e,
        };
        return try array_list.toOwnedSlice();
    }

    pub inline fn readUntilDelimiterOrEof(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        buf: []u8,
        delimiter: u8,
    ) (reader_impl.ReadError || error{StreamTooLong})!?[]u8 {
        var fbs = std.io.fixedBufferStream(buf);
        streamUntilDelimiter(
            reader_ctx,
            fbs.writer(),
            delimiter,
            fbs.buffer.len,
        ) catch |err| switch (err) {
            error.EndOfStream => if (fbs.getWritten().len == 0) {
                return null;
            },

            else => |e| return e,
        };
        const output = fbs.getWritten();
        buf[output.len] = delimiter; // emulating old behaviour
        return output;
    }

    pub inline fn streamUntilDelimiter(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        writer: anytype,
        delimiter: u8,
        optional_max_size: ?usize,
    ) (reader_impl.ReadError || error{ EndOfStream, StreamTooLong })!void {
        if (optional_max_size) |max_size| {
            for (0..max_size) |_| {
                const byte: u8 = try readByte(reader_ctx);
                if (byte == delimiter) return;
                try writer.writeByte(byte);
            }
            return error.StreamTooLong;
        } else {
            while (true) {
                const byte: u8 = try readByte(reader_ctx);
                if (byte == delimiter) return;
                try writer.writeByte(byte);
            }
            // Can not throw `error.StreamTooLong` since there are no
            // boundary.
        }
    }

    pub inline fn skipUntilDelimiterOrEof(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        delimiter: u8,
    ) reader_impl.ReadError!void {
        while (true) {
            const byte = readByte(reader_ctx) catch |err| switch (err) {
                error.EndOfStream => return,
                else => |e| return e,
            };
            if (byte == delimiter) return;
        }
    }

    pub inline fn readByte(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
    ) (reader_impl.ReadError || error{EndOfStream})!u8 {
        var result: [1]u8 = undefined;
        const amt_read = try read(reader_ctx, reader_impl, result[0..]);
        if (amt_read < 1) return error.EndOfStream;
        return result[0];
    }

    pub inline fn readByteSigned(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
    ) (reader_impl.ReadError || error{EndOfStream})!i8 {
        return @as(i8, @bitCast(try readByte(reader_ctx)));
    }

    pub inline fn readBytesNoEof(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        comptime num_bytes: usize,
    ) (reader_impl.ReadError || error{EndOfStream})![num_bytes]u8 {
        var bytes: [num_bytes]u8 = undefined;
        try readNoEof(reader_ctx, &bytes);
        return bytes;
    }

    pub inline fn readIntoBoundedBytes(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        comptime num_bytes: usize,
        bounded: *std.BoundedArray(u8, num_bytes),
    ) reader_impl.ReadError!void {
        while (bounded.len < num_bytes) {
            // get at most the number of bytes free in the bounded array
            const bytes_read = try read(
                reader_ctx,
                reader_impl,
                bounded.unusedCapacitySlice(),
            );
            if (bytes_read == 0) return;

            // bytes_read will never be larger than @TypeOf(bounded.len)
            // due to `read` being bounded by
            // `bounded.unusedCapacitySlice()`
            bounded.len += @as(@TypeOf(bounded.len), @intCast(bytes_read));
        }
    }

    pub inline fn readBoundedBytes(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        comptime num_bytes: usize,
    ) reader_impl.ReadError!std.BoundedArray(u8, num_bytes) {
        var result = std.BoundedArray(u8, num_bytes){};
        try readIntoBoundedBytes(reader_ctx, num_bytes, &result);
        return result;
    }

    pub inline fn readInt(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        comptime T: type,
        endian: std.builtin.Endian,
    ) (reader_impl.ReadError || error{EndOfStream})!T {
        const bytes = try readBytesNoEof(
            reader_ctx,
            @divExact(@typeInfo(T).Int.bits, 8),
        );
        return mem.readInt(T, &bytes, endian);
    }

    pub inline fn readVarInt(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        comptime ReturnType: type,
        endian: std.builtin.Endian,
        size: usize,
    ) (reader_impl.ReadError || error{EndOfStream})!ReturnType {
        assert(size <= @sizeOf(ReturnType));
        var bytes_buf: [@sizeOf(ReturnType)]u8 = undefined;
        const bytes = bytes_buf[0..size];
        try readNoEof(reader_ctx, bytes);
        return mem.readVarInt(ReturnType, bytes, endian);
    }

    pub inline fn skipBytes(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        num_bytes: u64,
        comptime options: struct {
            buf_size: usize = 512,
        },
    ) (reader_impl.ReadError || error{EndOfStream})!void {
        var buf: [options.buf_size]u8 = undefined;
        var remaining = num_bytes;

        while (remaining > 0) {
            const amt = @min(remaining, options.buf_size);
            try readNoEof(reader_ctx, buf[0..amt]);
            remaining -= amt;
        }
    }

    pub inline fn isBytes(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        slice: []const u8,
    ) (reader_impl.ReadError || error{EndOfStream})!bool {
        var i: usize = 0;
        var matches = true;
        while (i < slice.len) : (i += 1) {
            if (slice[i] != try readByte(reader_ctx)) {
                matches = false;
            }
        }
        return matches;
    }

    pub inline fn readStruct(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        comptime T: type,
    ) (reader_impl.ReadError || error{EndOfStream})!T {
        // Only extern and packed structs have defined in-memory layout.
        comptime assert(@typeInfo(T).Struct.layout != .Auto);
        var res: [1]T = undefined;
        try readNoEof(reader_ctx, mem.sliceAsBytes(res[0..]));
        return res[0];
    }

    pub inline fn readStructBig(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        comptime T: type,
    ) (reader_impl.ReadError || error{EndOfStream})!T {
        var res = try readStruct(reader_ctx, T);
        if (native_endian != std.builtin.Endian.big) {
            mem.byteSwapAllFields(T, &res);
        }
        return res;
    }

    pub inline fn readEnum(
        reader_ctx: anytype,
        comptime reader_impl: Impl(@TypeOf(reader_ctx), Reader),
        comptime Enum: type,
        endian: std.builtin.Endian,
    ) (reader_impl.ReadError || error{ EndOfStream, InvalidValue })!Enum {
        const E = error{
            /// An integer was read, but it did not match any of the tags
            /// in the supplied enum.
            InvalidValue,
        };
        const type_info = @typeInfo(Enum).Enum;
        const tag = try readInt(reader_ctx, type_info.tag_type, endian);

        inline for (std.meta.fields(Enum)) |field| {
            if (tag == field.value) {
                return @field(Enum, field.name);
            }
        }

        return E.InvalidValue;
    }
};

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

test "explicit implementation" {
    const in_buf: []const u8 = "I really hope that this works!";
    var reader = MyReader{ .buffer = in_buf, .pos = 0 };
    var out_buf: [16]u8 = undefined;
    const len = try IO.readAll(&reader, .{}, &out_buf);
    try testing.expectEqualSlices(u8, in_buf[0..len], out_buf[0..len]);
}
