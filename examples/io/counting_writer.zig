const std = @import("std");
const testing = std.testing;

const zimpl = @import("zimpl");
const Impl = zimpl.Impl;

const io = @import("../io.zig");

pub fn CountingWriter(
    comptime ChildCtx: type,
    comptime child_impl: Impl(ChildCtx, io.Writer),
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
    child_impl: Impl(@TypeOf(child_ctx), io.Writer),
) CountingWriter(@TypeOf(child_ctx), child_impl) {
    return .{ .child_ctx = child_ctx };
}
