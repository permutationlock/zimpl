const std = @import("std");
const io = @import("io");

const LOOPS = 1000;

pub fn main() !void {
    var in: [10000]u8 = undefined;
    try std.os.getrandom(&in);
    var fbr = io.FixedBufferReader{ .buffer = &in };

    var out: [10000]u8 = undefined;
    var out_stream = io.FixedBufferStream{ .buffer = &out };

    {
        // time buffered stream
        var found: usize = 0;
        var bytes: usize = 0;

        io.seekTo(&out_stream, .{}, 0) catch unreachable;
        var timer = try std.time.Timer.start();

        for (0..LOOPS) |_| {
            io.seekTo(&fbr, .{}, 0) catch unreachable;

            while (true) {
                io.streamUntilDelimiter(
                    &fbr,
                    .{},
                    &out_stream,
                    .{},
                    '\n',
                    out.len,
                ) catch |err| switch (err) {
                    error.EndOfStream => break,
                    else => return err,
                };

                found += 1;
                bytes += out_stream.getWritten().len;
                io.seekTo(&out_stream, .{}, 0) catch unreachable;
            }
        }
        const elapsed = timer.lap();
        std.debug.print(
            "Took: {d}us ({d}ns / iteration) {d} entries, {d} bytes\n",
            .{ elapsed / 1000, elapsed / LOOPS, found, bytes },
        );
    }

    {
        // time unbuffered stream
        var found: usize = 0;
        var bytes: usize = 0;

        io.seekTo(&out_stream, .{}, 0) catch unreachable;
        var timer = try std.time.Timer.start();

        for (0..LOOPS) |_| {
            io.seekTo(&fbr, .{}, 0) catch unreachable;

            while (true) {
                // use as unbuffered reader by setting 'getBuffer = null'
                io.streamUntilDelimiter(
                    &fbr,
                    .{ .getBuffer = null },
                    &out_stream,
                    .{},
                    '\n',
                    out.len,
                ) catch |err| switch (err) {
                    error.EndOfStream => break,
                    else => return err,
                };

                found += 1;
                bytes += out_stream.getWritten().len;
                io.seekTo(&out_stream, .{}, 0) catch unreachable;
            }
        }
        const elapsed = timer.lap();
        std.debug.print(
            "Took: {d}us ({d}ns / iteration) {d} entries, {d} bytes\n",
            .{ elapsed / 1000, elapsed / LOOPS, found, bytes },
        );
    }
}
