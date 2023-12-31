const std = @import("std");
const testing = std.testing;

const Impl = @import("zimpl").Impl;

const io = @import("../io.zig");
const vio = @import("../vio.zig");

pub fn BufferedReader(
    comptime buffer_size: usize,
    comptime ChildCtx: type,
    comptime child_impl: Impl(io.Reader, ChildCtx),
) type {
    return struct {
        child_ctx: ChildCtx,
        buffer: [buffer_size]u8 = undefined,
        start: usize = 0,
        end: usize = 0,

        pub const ReadError = child_impl.ReadError;

        fn fillBuffer(self: *@This()) ReadError!void {
            self.start = 0;
            self.end = try io.read(
                self.child_ctx,
                child_impl,
                self.buffer[0..],
            );
        }

        pub fn read(self: *@This(), dest: []u8) ReadError!usize {
            var dest_index: usize = 0;
            while (dest_index < dest.len) {
                const written = @min(
                    dest.len - dest_index,
                    self.end - self.start,
                );
                @memcpy(
                    dest[dest_index..][0..written],
                    self.buffer[self.start..][0..written],
                );
                if (written == 0) {
                    try self.fillBuffer();
                    if (self.start == self.end) {
                        return dest_index;
                    }
                }
                self.start += written;
                dest_index += written;
            }
            return dest.len;
        }

        pub fn readBuffer(self: *@This()) ReadError![]const u8 {
            if (self.start == self.end) {
                try self.fillBuffer();
            }
            return self.buffer[self.start..self.end];
        }
    };
}

pub fn bufferedReader(
    comptime buffer_size: usize,
    child_ctx: anytype,
    child_impl: Impl(io.Reader, @TypeOf(child_ctx)),
) BufferedReader(buffer_size, @TypeOf(child_ctx), child_impl) {
    return .{ .child_ctx = child_ctx };
}

test "buffered fixed buffer reader" {
    const buffer = "Hello! Is anybody there?";
    var fb_reader = io.FixedBufferReader{ .buffer = buffer };
    var buff_reader = bufferedReader(8, &fb_reader, .{});
    try std.testing.expect(io.isBufferedReader(@TypeOf(&buff_reader), .{}));

    var out_bytes: [buffer.len]u8 = undefined;
    const len = try io.readAll(&buff_reader, .{}, &out_bytes);
    try std.testing.expectEqual(buffer.len, len);
    try std.testing.expectEqualStrings(buffer, &out_bytes);
}

test "virtual buffered fixed buffer reader" {
    const buffer = "Hello! Is anybody there?";
    var fb_reader = io.FixedBufferReader{ .buffer = buffer };
    var buff_reader = bufferedReader(8, &fb_reader, .{});
    const reader = vio.makeReader(.Direct, &buff_reader, .{});
    try std.testing.expect(vio.isBufferedReader(reader));

    var out_bytes: [buffer.len]u8 = undefined;
    const len = try vio.readAll(reader, &out_bytes);
    try std.testing.expectEqual(buffer.len, len);
    try std.testing.expectEqualStrings(buffer, &out_bytes);
}
