const std = @import("std");
const zstd = @import("zstd.zig");
const FixedBufferStream = zstd.io.FixedBufferStream;

test {
    var file = try std.fs.cwd().openFile("examples/read_file/test.txt", .{});
    var buffer: [32]u8 = undefined;
    var fbs: FixedBufferStream = .{ .buffer = &buffer };
    try zstd.io.streamUntilDelimiter(file, .{}, &fbs, .{}, '\n', 32);
    try std.testing.expectEqualStrings(
        "Hello, I am a file!",
        fbs.getWritten(),
    );
}
