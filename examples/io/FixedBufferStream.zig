const std = @import("std");
const testing = std.testing;

const io = @import("../io.zig");

buffer: []u8,
pos: usize = 0,

pub const ReadError = error{};
pub const WriteError = error{NoSpaceLeft};
pub const SeekError = error{};
pub const GetSeekPosError = error{};

pub fn read(self: *@This(), out_buffer: []u8) ReadError!usize {
    const len = @min(self.buffer[self.pos..].len, out_buffer.len);
    @memcpy(
        out_buffer[0..len],
        self.buffer[self.pos..][0..len],
    );
    self.pos += len;
    return len;
}

pub fn readBuffer(self: *const @This()) ReadError![]u8 {
    return self.buffer[self.pos..];
}

pub fn write(self: *@This(), in_buffer: []const u8) WriteError!usize {
    const len = @min(self.buffer[self.pos..].len, in_buffer.len);
    if (len == 0) {
        return WriteError.NoSpaceLeft;
    }
    @memcpy(
        self.buffer[self.pos..][0..len],
        in_buffer[0..len],
    );
    self.pos += len;
    return len;
}

pub fn seekTo(self: *@This(), pos: u64) SeekError!void {
    if (std.math.cast(usize, pos)) |usize_pos| {
        self.pos = @min(self.buffer.len, usize_pos);
    }
}

pub fn seekBy(self: *@This(), amt: i64) SeekError!void {
    const negate = amt < 0;
    if (std.math.cast(usize, @abs(amt))) |abs_amt| {
        if (negate) {
            if (abs_amt > self.pos) {
                self.pos = 0;
            } else {
                self.pos -= abs_amt;
            }
        } else {
            self.pos += abs_amt;
        }
    }
}

pub fn getPos(self: *const @This()) GetSeekPosError!u64 {
    return self.pos;
}

pub fn getEndPos(self: *const @This()) GetSeekPosError!u64 {
    return self.buffer.len;
}

pub fn getWritten(self: *const @This()) []u8 {
    return self.buffer[0..self.pos];
}

test "write, seek 0, and read back" {
    const in_buf: []const u8 = "I really hope that this works!";

    var stream_buf: [in_buf.len]u8 = undefined;
    var stream = @This(){ .buffer = &stream_buf, .pos = 0 };

    try io.writeAll(&stream, .{}, in_buf);

    var out_buf: [in_buf.len]u8 = undefined;
    try io.seekTo(&stream, .{}, 0);
    try testing.expectEqual(@as(u64, 0), try io.getPos(&stream, .{}));

    const rlen = try io.readAll(&stream, .{}, &out_buf);
    try testing.expectEqual(in_buf.len, rlen);
    try testing.expectEqualSlices(u8, in_buf, &out_buf);
}

test "FixedBufferStream is a buffered io.Reader" {
    const impl = @import("zimpl").Impl(io.Reader, *@This()){};
    try std.testing.expect(!(impl.readBuffer == null));
}
