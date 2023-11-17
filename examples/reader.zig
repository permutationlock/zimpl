const std = @import("std");
const testing = std.testing;
const native_endian = @import("builtin").target.cpu.arch.endian();
const mem = std.mem;
const assert = std.debug.assert;

const zimpl = @import("zimpl");

pub fn Reader(comptime Self: type) type {
    const Type = zimpl.Unwrap(Self);
    return struct {
        pub const read = fn (self: Self, buffer: []u8) anyerror!usize;

        pub inline fn readAll(self: Self, buffer: []u8) anyerror!usize {
            return readAtLeast(self, buffer, buffer.len);
        }

        pub inline fn readAtLeast(
            self: Self,
            buffer: []u8,
            len: usize,
        ) anyerror!usize {
            assert(len <= buffer.len);
            var index: usize = 0;
            while (index < len) {
                const amt = try Type.read(self, buffer[index..]);
                if (amt == 0) break;
                index += amt;
            }
            return index;
        }

        pub inline fn readNoEof(self: Self, buf: []u8) anyerror!void {
            const amt_read = try readAll(self, buf);
            if (amt_read < buf.len) return error.EndOfStream;
        }

        pub inline fn readAllArrayList(
            self: Self,
            array_list: *std.ArrayList(u8),
            max_append_size: usize,
        ) anyerror!void {
            return readAllArrayListAligned(
                self,
                null,
                array_list,
                max_append_size,
            );
        }

        pub inline fn readAllArrayListAligned(
            self: Self,
            comptime alignment: ?u29,
            array_list: *std.ArrayListAligned(u8, alignment),
            max_append_size: usize,
        ) anyerror!void {
            try array_list.ensureTotalCapacity(@min(max_append_size, 4096));
            const original_len = array_list.items.len;
            var start_index: usize = original_len;
            while (true) {
                array_list.expandToCapacity();
                const dest_slice = array_list.items[start_index..];
                const bytes_read = try readAll(self, dest_slice);
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
            self: Self,
            allocator: mem.Allocator,
            max_size: usize,
        ) anyerror![]u8 {
            var array_list = std.ArrayList(u8).init(allocator);
            defer array_list.deinit();
            try readAllArrayList(self, &array_list, max_size);
            return try array_list.toOwnedSlice();
        }

        pub inline fn readUntilDelimiterArrayList(
            self: Self,
            array_list: *std.ArrayList(u8),
            delimiter: u8,
            max_size: usize,
        ) anyerror!void {
            array_list.shrinkRetainingCapacity(0);
            try streamUntilDelimiter(
                self,
                array_list.writer(),
                delimiter,
                max_size,
            );
        }

        pub inline fn readUntilDelimiterAlloc(
            self: Self,
            allocator: mem.Allocator,
            delimiter: u8,
            max_size: usize,
        ) anyerror![]u8 {
            var array_list = std.ArrayList(u8).init(allocator);
            defer array_list.deinit();
            try streamUntilDelimiter(self, array_list.writer(), delimiter, max_size);
            return try array_list.toOwnedSlice();
        }

        pub inline fn readUntilDelimiter(
            self: Self,
            buf: []u8,
            delimiter: u8,
        ) anyerror![]u8 {
            var fbs = std.io.fixedBufferStream(buf);
            try streamUntilDelimiter(
                self,
                fbs.writer(),
                delimiter,
                fbs.buffer.len,
            );
            const output = fbs.getWritten();
            buf[output.len] = delimiter; // emulating old behaviour
            return output;
        }

        pub inline fn readUntilDelimiterOrEofAlloc(
            self: Self,
            allocator: mem.Allocator,
            delimiter: u8,
            max_size: usize,
        ) anyerror!?[]u8 {
            var array_list = std.ArrayList(u8).init(allocator);
            defer array_list.deinit();
            streamUntilDelimiter(
                self,
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
            self: Self,
            buf: []u8,
            delimiter: u8,
        ) anyerror!?[]u8 {
            var fbs = std.io.fixedBufferStream(buf);
            streamUntilDelimiter(
                self,
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
            self: Self,
            writer: anytype,
            delimiter: u8,
            optional_max_size: ?usize,
        ) anyerror!void {
            if (optional_max_size) |max_size| {
                for (0..max_size) |_| {
                    const byte: u8 = try readByte(self);
                    if (byte == delimiter) return;
                    try writer.writeByte(byte);
                }
                return error.StreamTooLong;
            } else {
                while (true) {
                    const byte: u8 = try readByte(self);
                    if (byte == delimiter) return;
                    try writer.writeByte(byte);
                }
                // Can not throw `error.StreamTooLong` since there are no boundary.
            }
        }

        pub inline fn skipUntilDelimiterOrEof(
            self: Self,
            delimiter: u8,
        ) anyerror!void {
            while (true) {
                const byte = readByte(self) catch |err| switch (err) {
                    error.EndOfStream => return,
                    else => |e| return e,
                };
                if (byte == delimiter) return;
            }
        }

        pub inline fn readByte(self: Self) anyerror!u8 {
            var result: [1]u8 = undefined;
            const amt_read = try Type.read(self, result[0..]);
            if (amt_read < 1) return error.EndOfStream;
            return result[0];
        }

        pub inline fn readByteSigned(self: Self) anyerror!i8 {
            return @as(i8, @bitCast(try readByte(self)));
        }

        pub inline fn readBytesNoEof(
            self: Self,
            comptime num_bytes: usize,
        ) anyerror![num_bytes]u8 {
            var bytes: [num_bytes]u8 = undefined;
            try readNoEof(self, &bytes);
            return bytes;
        }

        pub inline fn readIntoBoundedBytes(
            self: Self,
            comptime num_bytes: usize,
            bounded: *std.BoundedArray(u8, num_bytes),
        ) anyerror!void {
            while (bounded.len < num_bytes) {
                // get at most the number of bytes free in the bounded array
                const bytes_read = try Type.read(
                    self,
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
            self: Self,
            comptime num_bytes: usize,
        ) anyerror!std.BoundedArray(u8, num_bytes) {
            var result = std.BoundedArray(u8, num_bytes){};
            try readIntoBoundedBytes(self, num_bytes, &result);
            return result;
        }

        pub inline fn readInt(
            self: Self,
            comptime T: type,
            endian: std.builtin.Endian,
        ) anyerror!T {
            const bytes = try readBytesNoEof(
                self,
                @divExact(@typeInfo(T).Int.bits, 8),
            );
            return mem.readInt(T, &bytes, endian);
        }

        pub inline fn readVarInt(
            self: Self,
            comptime ReturnType: type,
            endian: std.builtin.Endian,
            size: usize,
        ) anyerror!ReturnType {
            assert(size <= @sizeOf(ReturnType));
            var bytes_buf: [@sizeOf(ReturnType)]u8 = undefined;
            const bytes = bytes_buf[0..size];
            try readNoEof(self, bytes);
            return mem.readVarInt(ReturnType, bytes, endian);
        }

        pub inline fn skipBytes(
            self: Self,
            num_bytes: u64,
            comptime options: struct {
                buf_size: usize = 512,
            },
        ) anyerror!void {
            var buf: [options.buf_size]u8 = undefined;
            var remaining = num_bytes;

            while (remaining > 0) {
                const amt = @min(remaining, options.buf_size);
                try readNoEof(self, buf[0..amt]);
                remaining -= amt;
            }
        }

        pub inline fn isBytes(self: Self, slice: []const u8) anyerror!bool {
            var i: usize = 0;
            var matches = true;
            while (i < slice.len) : (i += 1) {
                if (slice[i] != try readByte(self)) {
                    matches = false;
                }
            }
            return matches;
        }

        pub inline fn readStruct(self: Self, comptime T: type) anyerror!T {
            // Only extern and packed structs have defined in-memory layout.
            comptime assert(@typeInfo(T).Struct.layout != .Auto);
            var res: [1]T = undefined;
            try readNoEof(self, mem.sliceAsBytes(res[0..]));
            return res[0];
        }

        pub inline fn readStructBig(self: Self, comptime T: type) anyerror!T {
            var res = try readStruct(self, T);
            if (native_endian != std.builtin.Endian.big) {
                mem.byteSwapAllFields(T, &res);
            }
            return res;
        }

        pub inline fn readEnum(
            self: Self,
            comptime Enum: type,
            endian: std.builtin.Endian,
        ) anyerror!Enum {
            const E = error{
                /// An integer was read, but it did not match any of the tags
                /// in the supplied enum.
                InvalidValue,
            };
            const type_info = @typeInfo(Enum).Enum;
            const tag = try readInt(self, type_info.tag_type, endian);

            inline for (std.meta.fields(Enum)) |field| {
                if (tag == field.value) {
                    return @field(Enum, field.name);
                }
            }

            return E.InvalidValue;
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

test "explicit implementation" {
    const in_buf: []const u8 = "I really hope that this works!";
    var reader = MyReader{ .buffer = in_buf, .pos = 0 };
    var out_buf: [16]u8 = undefined;
    try readFromReader(&reader, .{}, &out_buf);
    try testing.expectEqualSlices(u8, in_buf[0..out_buf.len], &out_buf);
}
