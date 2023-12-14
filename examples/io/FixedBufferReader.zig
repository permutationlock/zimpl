const std = @import("std");
const testing = std.testing;

const io = @import("../io.zig");
const vio = @import("../vio.zig");

buffer: []const u8,
pos: usize = 0,

pub const ReadError = error{};

pub fn read(self: *@This(), out_buffer: []u8) ReadError!usize {
    const len = @min(self.buffer[self.pos..].len, out_buffer.len);
    @memcpy(
        out_buffer[0..len],
        self.buffer[self.pos..][0..len],
    );
    self.pos += len;
    return len;
}

pub fn readBuffer(self: *const @This()) ReadError![]const u8 {
    return self.buffer[self.pos..];
}

pub fn seekTo(self: *@This(), pos: u64) error{}!void {
    if (std.math.cast(usize, pos)) |usize_pos| {
        self.pos = @min(self.buffer.len, usize_pos);
    }
}

pub fn seekBy(self: *@This(), amt: i64) error{}!void {
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

pub fn getPos(self: *const @This()) error{}!u64 {
    return self.pos;
}

pub fn getEndPos(self: *const @This()) error{}!u64 {
    return self.buffer.len;
}

test "read and seek" {
    const buffer: []const u8 = "I really hope that this works!";
    var stream = @This(){ .buffer = buffer, .pos = 0 };

    var out_buf: [buffer.len]u8 = undefined;
    const len1 = try io.readAll(&stream, .{}, &out_buf);
    try testing.expectEqual(buffer.len, len1);
    try testing.expectEqualSlices(u8, buffer, &out_buf);

    try io.seekTo(&stream, .{}, 0);
    try testing.expectEqual(@as(u64, 0), try io.getPos(&stream, .{}));

    const len2 = try io.readAll(&stream, .{}, &out_buf);
    try testing.expectEqual(buffer.len, len2);
    try testing.expectEqualSlices(u8, buffer, &out_buf);
}

test "virtual read" {
    const buffer: []const u8 = "I really hope that this works!";
    var stream = @This(){ .buffer = buffer, .pos = 0 };
    const reader = vio.makeReader(&stream, .{});

    var out_buf: [buffer.len]u8 = undefined;
    const len1 = try vio.readAll(reader, &out_buf);
    try testing.expectEqual(buffer.len, len1);
    try testing.expectEqualSlices(u8, buffer, &out_buf);
}

test "FixedBufferReader is a buffered io.Reader" {
    try std.testing.expect(io.isBufferedReader(*@This(), .{}));
}
