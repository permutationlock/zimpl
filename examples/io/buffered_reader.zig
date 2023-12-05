const std = @import("std");
const testing = std.testing;

const Impl = @import("zimpl").Impl;

const io = @import("../io.zig");

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
                    const n = try io.read(
                        self.child_ctx,
                        child_impl,
                        self.buffer[0..],
                    );
                    if (n == 0) {
                        return dest_index;
                    }
                    self.start = 0;
                    self.end = n;
                }
                self.start += written;
                dest_index += written;
            }
            return dest.len;
        }

        pub fn getBuffer(self: *const @This()) []const u8 {
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
    var out_bytes: [buffer.len]u8 = undefined;
    const len = try io.readAll(&buff_reader, .{}, &out_bytes);
    try std.testing.expectEqual(buffer.len, len);
    try std.testing.expectEqualStrings(buffer, &out_bytes);
}
