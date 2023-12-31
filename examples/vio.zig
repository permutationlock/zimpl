const std = @import("std");
const native_endian = @import("builtin").target.cpu.arch.endian();
const mem = std.mem;
const assert = std.debug.assert;

const zimpl = @import("zimpl");
const VIfc = zimpl.VIfc;
const makeVIfc = zimpl.makeVIfc;

const io = @import("io.zig");

pub const Reader = VIfc(io.Reader);
pub const makeReader = makeVIfc(io.Reader);

pub inline fn read(reader: Reader, buffer: []u8) anyerror!usize {
    return reader.vtable.read(reader.ctx, buffer);
}

pub inline fn isBufferedReader(reader: Reader) bool {
    return !(reader.vtable.readBuffer == null);
}

pub inline fn readBuffer(reader: Reader) anyerror![]const u8 {
    if (reader.vtable.readBuffer) |readBufferFn| {
        return readBufferFn(reader.ctx);
    }
    @panic("called 'readBuffer' on an unbuffered reader");
}

pub inline fn readAll(
    reader: Reader,
    buffer: []u8,
) anyerror!usize {
    return readAtLeast(reader, buffer, buffer.len);
}

pub fn readAtLeast(reader: Reader, buffer: []u8, len: usize) anyerror!usize {
    assert(len <= buffer.len);
    var index: usize = 0;
    while (index < len) {
        const amt = try read(reader, buffer[index..]);
        if (amt == 0) break;
        index += amt;
    }
    return index;
}

pub fn readNoEof(reader: Reader, buf: []u8) anyerror!void {
    const amt_read = try readAll(reader, buf);
    if (amt_read < buf.len) return error.EndOfStream;
}

pub fn streamUntilDelimiter(
    reader: Reader,
    writer: Writer,
    delimiter: u8,
    optional_max_size: ?usize,
) anyerror!void {
    if (isBufferedReader(reader)) {
        while (true) {
            const buffer = try readBuffer(reader);
            if (buffer.len == 0) {
                return error.EndOfStream;
            }
            const len = std.mem.indexOfScalar(
                u8,
                buffer,
                delimiter,
            ) orelse buffer.len;
            if (optional_max_size) |max| {
                if (len > max) {
                    return error.StreamTooLong;
                }
            }

            try writeAll(writer, buffer[0..len]);
            if (len != buffer.len) {
                return skipBytes(reader, len + 1, .{});
            }
            try skipBytes(reader, len, .{});
        }
    } else {
        if (optional_max_size) |max_size| {
            for (0..max_size) |_| {
                const byte: u8 = try readByte(reader);
                if (byte == delimiter) return;
                try writeByte(writer, byte);
            }
            return error.StreamTooLong;
        } else {
            while (true) {
                const byte: u8 = try readByte(reader);
                if (byte == delimiter) return;
                try writeByte(writer, byte);
            }
        }
    }
}

pub fn skipUntilDelimiterOrEof(reader: Reader, delimiter: u8) anyerror!void {
    if (isBufferedReader(reader)) {
        while (true) {
            const buffer = try readBuffer(reader);
            if (buffer.len == 0) {
                return;
            }
            const len = std.mem.indexOfScalar(
                u8,
                buffer,
                delimiter,
            ) orelse buffer.len;
            if (len != buffer.len) {
                skipBytes(reader, len + 1, .{}) catch unreachable;
                return;
            }
            skipBytes(reader, len, .{}) catch unreachable;
        }
    } else {
        while (true) {
            const byte = readByte(reader) catch |err| switch (err) {
                error.EndOfStream => return,
                else => |e| return e,
            };
            if (byte == delimiter) return;
        }
    }
}

pub fn readByte(reader: Reader) anyerror!u8 {
    var result: [1]u8 = undefined;
    const amt_read = try read(reader, result[0..]);
    if (amt_read < 1) return error.EndOfStream;
    return result[0];
}

pub fn readByteSigned(reader: Reader) anyerror!i8 {
    return @as(i8, @bitCast(try readByte(reader)));
}

pub fn readBytesNoEof(
    reader: Reader,
    comptime num_bytes: usize,
) anyerror![num_bytes]u8 {
    var bytes: [num_bytes]u8 = undefined;
    try readNoEof(reader, &bytes);
    return bytes;
}

pub fn readInt(
    reader: Reader,
    comptime T: type,
    endian: std.builtin.Endian,
) anyerror!T {
    const bytes = try readBytesNoEof(
        reader,
        @divExact(@typeInfo(T).Int.bits, 8),
    );
    return mem.readInt(T, &bytes, endian);
}

pub fn readVarInt(
    reader: Reader,
    comptime ReturnType: type,
    endian: std.builtin.Endian,
    size: usize,
) anyerror!ReturnType {
    assert(size <= @sizeOf(ReturnType));
    var bytes_buf: [@sizeOf(ReturnType)]u8 = undefined;
    const bytes = bytes_buf[0..size];
    try readNoEof(reader, bytes);
    return mem.readVarInt(ReturnType, bytes, endian);
}

pub fn skipBytes(
    reader: Reader,
    num_bytes: u64,
    comptime options: struct {
        buf_size: usize = 512,
    },
) anyerror!void {
    var buf: [options.buf_size]u8 = undefined;
    var remaining = num_bytes;

    while (remaining > 0) {
        const amt = @min(remaining, options.buf_size);
        try readNoEof(reader, buf[0..amt]);
        remaining -= amt;
    }
}

pub fn isBytes(reader: Reader, slice: []const u8) anyerror!bool {
    var i: usize = 0;
    var matches = true;
    while (i < slice.len) {
        if (isBufferedReader(reader)) {
            const buffer = try readBuffer(reader);
            const len = @min(buffer.len, slice.len - i);
            if (len == 0) {
                return error.EndOfStream;
            }
            if (!std.mem.eql(u8, slice[i..][0..len], buffer[0..len])) {
                matches = false;
            }
            try skipBytes(reader, len, .{});
            i += len;
        } else {
            if (slice[i] != try readByte(reader)) {
                matches = false;
            }
            i += 1;
        }
    }
    return matches;
}

pub fn readStruct(reader: Reader, comptime T: type) anyerror!T {
    comptime assert(@typeInfo(T).Struct.layout != .Auto);
    var res: [1]T = undefined;
    try readNoEof(reader, mem.sliceAsBytes(res[0..]));
    return res[0];
}

pub fn readStructBig(reader: Reader, comptime T: type) anyerror!T {
    var res = try readStruct(reader, T);
    if (native_endian != std.builtin.Endian.big) {
        mem.byteSwapAllFields(T, &res);
    }
    return res;
}

pub fn readEnum(
    reader: Reader,
    comptime Enum: type,
    endian: std.builtin.Endian,
) anyerror!Enum {
    const type_info = @typeInfo(Enum).Enum;
    const tag = try readInt(reader, type_info.tag_type, endian);

    inline for (std.meta.fields(Enum)) |field| {
        if (tag == field.value) {
            return @field(Enum, field.name);
        }
    }

    return error.InvalidValue;
}

pub const Writer = VIfc(io.Writer);
pub const makeWriter = makeVIfc(io.Writer);

pub inline fn write(writer: Writer, bytes: []const u8) anyerror!usize {
    return writer.vtable.write(writer.ctx, bytes);
}

pub inline fn flushBuffer(writer: Writer) anyerror!void {
    if (writer.vtable.flushBuffer) |flushFn| {
        return flushFn(writer.ctx);
    }
}

pub fn writeAll(writer: Writer, bytes: []const u8) anyerror!void {
    var index: usize = 0;
    while (index != bytes.len) {
        index += try write(writer, bytes[index..]);
    }
}

pub fn writeByte(writer: Writer, byte: u8) anyerror!void {
    const array = [1]u8{byte};
    return writeAll(writer, &array);
}

pub fn writeByteNTimes(
    writer: Writer,
    byte: u8,
    n: usize,
) anyerror!void {
    var bytes: [256]u8 = undefined;
    @memset(bytes[0..], byte);

    var remaining: usize = n;
    while (remaining > 0) {
        const to_write = @min(remaining, bytes.len);
        try writeAll(writer, bytes[0..to_write]);
        remaining -= to_write;
    }
}

pub fn writeInt(
    writer: Writer,
    comptime T: type,
    value: T,
    endian: std.builtin.Endian,
) anyerror!void {
    var bytes: [@divExact(@typeInfo(T).Int.bits, 8)]u8 = undefined;
    mem.writeInt(
        std.math.ByteAlignedInt(@TypeOf(value)),
        &bytes,
        value,
        endian,
    );
    return writeAll(writer, &bytes);
}

pub fn writeStruct(writer: Writer, value: anytype) anyerror!void {
    comptime assert(@typeInfo(@TypeOf(value)).Struct.layout != .Auto);
    return writeAll(writer, mem.asBytes(&value));
}

test {
    std.testing.refAllDecls(@This());
}
