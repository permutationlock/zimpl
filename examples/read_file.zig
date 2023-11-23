const std = @import("std");
const io = @import("io.zig");
const FixedBufferStream = io.FixedBufferStream;

test {
    const file = try std.fs.cwd().openFile("examples/read_file/test.txt", .{});
    var buffer: [32]u8 = undefined;
    var fbs: FixedBufferStream = .{ .buffer = &buffer };
    try io.streamUntilDelimiter(file, .{}, &fbs, .{}, '\n', 32);
    try std.testing.expectEqualStrings(
        "Hello, I am a file!",
        fbs.getWritten(),
    );
}
