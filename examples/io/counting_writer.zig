const std = @import("std");
const testing = std.testing;

const io = @import("../io.zig");

pub fn CountingWriter(
    comptime ChildCtx: type,
    comptime child_impl: io.Writer(ChildCtx),
) type {
    return struct {
        child_ctx: ChildCtx,
        bytes_written: u64 = 0,

        pub const WriteError = child_impl.WriteError;

        pub fn write(self: *@This(), bytes: []const u8) WriteError!usize {
            const len = try io.write(self.child_ctx, child_impl, bytes);
            self.bytes_written += len;
            return len;
        }
    };
}

pub fn countingWriter(
    child_ctx: anytype,
    child_impl: io.Writer(@TypeOf(child_ctx)),
) CountingWriter(@TypeOf(child_ctx), child_impl) {
    return .{ .child_ctx = child_ctx };
}

test "count bytes written to null_writer" {
    var writer = countingWriter(io.null_writer, .{});
    try io.writeAll(&writer, .{}, "Hello!");
    try io.writeAll(&writer, .{}, "Is anybody there?");
    try std.testing.expectEqual(@as(usize, 23), writer.bytes_written);
}
