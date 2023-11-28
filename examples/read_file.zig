const std = @import("std");
const io = @import("io.zig");
const FixedBufferStream = io.FixedBufferStream;
const Impl = @import("zimpl").Impl;

test "read file with std.fs.File" {
    const file = try std.fs.cwd().openFile("examples/read_file/test.txt", .{});
    var buffer: [32]u8 = undefined;
    var fbs: FixedBufferStream = .{ .buffer = &buffer };
    try io.streamUntilDelimiter(file, .{}, &fbs, .{}, '\n', 32);
    try std.testing.expectEqualStrings(
        "Hello, I am a file!",
        fbs.getWritten(),
    );
}

test "read file with std.os.fd_t" {
    const fd = try std.os.open(
        "examples/read_file/test.txt",
        std.os.O.RDONLY,
        0,
    );
    const fd_reader: Impl(io.Reader, std.os.fd_t) = .{
        .read = std.os.read,
        .ReadError = std.os.ReadError,
    };
    var buffer: [32]u8 = undefined;
    var fbs: FixedBufferStream = .{ .buffer = &buffer };
    try io.streamUntilDelimiter(fd, fd_reader, &fbs, .{}, '\n', 32);
    try std.testing.expectEqualStrings(
        "Hello, I am a file!",
        fbs.getWritten(),
    );
}
