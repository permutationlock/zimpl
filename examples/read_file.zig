const std = @import("std");
const io = @import("io.zig");
const vio = @import("vio.zig");
const FixedBufferStream = io.FixedBufferStream;

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

test "read file with std.posix.fd_t" {
    const fd = try std.posix.open("examples/read_file/test.txt", .{}, 0);
    var buffer: [32]u8 = undefined;
    var fbs: FixedBufferStream = .{ .buffer = &buffer };
    try io.streamUntilDelimiter(
        fd,
        .{
            .read = std.posix.read,
            .ReadError = std.posix.ReadError,
        },
        &fbs,
        .{},
        '\n',
        32,
    );
    try std.testing.expectEqualStrings(
        "Hello, I am a file!",
        fbs.getWritten(),
    );
}

test "read file with buffered std.fs.File" {
    const file = try std.fs.cwd().openFile("examples/read_file/test.txt", .{});
    var buffered_file = io.bufferedReader(256, file, .{});
    var buffer: [32]u8 = undefined;
    var fbs: FixedBufferStream = .{ .buffer = &buffer };
    try io.streamUntilDelimiter(&buffered_file, .{}, &fbs, .{}, '\n', 32);
    try std.testing.expectEqualStrings(
        "Hello, I am a file!",
        fbs.getWritten(),
    );
}

test "read file with buffered std.posix.fd_t" {
    const fd = try std.posix.open(
        "examples/read_file/test.txt", .{}, 0);
    var buffered_fd = io.bufferedReader(256, fd, .{
        .read = std.posix.read,
        .ReadError = std.posix.ReadError,
    });
    var buffer: [32]u8 = undefined;
    var fbs: FixedBufferStream = .{ .buffer = &buffer };
    try io.streamUntilDelimiter(&buffered_fd, .{}, &fbs, .{}, '\n', 32);
    try std.testing.expectEqualStrings(
        "Hello, I am a file!",
        fbs.getWritten(),
    );
}

test "virtual read file with std.fs.File" {
    const file = try std.fs.cwd().openFile("examples/read_file/test.txt", .{});
    var buffer: [32]u8 = undefined;
    var fbs: FixedBufferStream = .{ .buffer = &buffer };
    try vio.streamUntilDelimiter(
        vio.Reader.init(.indirect, &file, .{}),
        vio.Writer.init(.direct, &fbs, .{}),
        '\n',
        32,
    );
    try std.testing.expectEqualStrings(
        "Hello, I am a file!",
        fbs.getWritten(),
    );
}

test "virtual read file with std.posix.fd_t" {
    const fd = try std.posix.open("examples/read_file/test.txt", .{}, 0);
    var buffer: [32]u8 = undefined;
    var fbs: FixedBufferStream = .{ .buffer = &buffer };
    try vio.streamUntilDelimiter(
        vio.Reader.init(.indirect, &fd, .{
            .read = std.posix.read,
            .ReadError = std.posix.ReadError,
        }),
        vio.Writer.init(.direct, &fbs, .{}),
        '\n',
        32,
    );
    try std.testing.expectEqualStrings(
        "Hello, I am a file!",
        fbs.getWritten(),
    );
}
