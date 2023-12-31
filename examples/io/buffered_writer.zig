const std = @import("std");
const testing = std.testing;

const Impl = @import("zimpl").Impl;

const io = @import("../io.zig");
const vio = @import("../vio.zig");

pub fn BufferedWriter(
    comptime buffer_size: usize,
    comptime ChildCtx: type,
    comptime child_impl: Impl(io.Writer, ChildCtx),
) type {
    return struct {
        child_ctx: ChildCtx,
        buffer: [buffer_size]u8 = undefined,
        end: usize = 0,

        pub const WriteError = child_impl.WriteError;

        pub fn flushBuffer(self: *@This()) WriteError!void {
            try io.writeAll(
                self.child_ctx,
                child_impl,
                self.buffer[0..self.end],
            );
            self.end = 0;
        }

        pub fn write(self: *@This(), bytes: []const u8) WriteError!usize {
            if (self.end + bytes.len > self.buffer.len) {
                try self.flushBuffer();
                if (bytes.len > self.buffer.len) {
                    return io.write(self.child_ctx, child_impl, bytes);
                }
            }
            const new_end = self.end + bytes.len;
            @memcpy(self.buffer[self.end..new_end], bytes);
            self.end = new_end;
            return bytes.len;
        }
    };
}

pub fn bufferedWriter(
    comptime buffer_size: usize,
    child_ctx: anytype,
    child_impl: Impl(io.Writer, @TypeOf(child_ctx)),
) BufferedWriter(buffer_size, @TypeOf(child_ctx), child_impl) {
    return .{ .child_ctx = child_ctx };
}

test "count bytes written to null_writer" {
    var count_writer = io.countingWriter(io.null_writer, .{});
    var buff_writer = bufferedWriter(8, &count_writer, .{});
    try io.writeAll(&buff_writer, .{}, "Hello!");
    try std.testing.expectEqual(@as(usize, 0), count_writer.bytes_written);
    try io.writeAll(&buff_writer, .{}, "Is anybody there?");
    try std.testing.expectEqual(@as(usize, 23), count_writer.bytes_written);
}

test "virtual count bytes written to null_writer" {
    var count_writer = io.countingWriter(io.null_writer, .{});
    var buff_writer = bufferedWriter(8, &count_writer, .{});
    const writer = vio.makeWriter(.Direct, &buff_writer, .{});
    try vio.writeAll(writer, "Hello!");
    try std.testing.expectEqual(@as(usize, 0), count_writer.bytes_written);
    try vio.writeAll(writer, "Is anybody there?");
    try std.testing.expectEqual(@as(usize, 23), count_writer.bytes_written);
}
