const std = @import("std");
const io = @import("io");

const LOOPS = 1000;

pub fn main() !void {
    var in: [10000]u8 = undefined;
    try std.os.getrandom(&in);

    {
        // time buffered generic stream
        var fbr = io.FixedBufferReader{ .buffer = &in };
        var out: [10000]u8 = undefined;
        var out_stream = io.FixedBufferStream{ .buffer = &out };

        var found: usize = 0;
        var bytes: usize = 0;

        var timer = try std.time.Timer.start();

        for (0..LOOPS) |_| {
            fbr.pos = 0;

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
                out_stream.pos = 0;
            }
        }
        const elapsed = timer.lap();
        std.debug.print(
            "Took: {d}us ({d}ns / iteration) {d} entries, {d} bytes\n",
            .{ elapsed / 1000, elapsed / LOOPS, found, bytes },
        );
    }

    {
        // time unbuffered generic stream
        var fbr = io.FixedBufferReader{ .buffer = &in };
        var out: [10000]u8 = undefined;
        var out_stream = io.FixedBufferStream{ .buffer = &out };
        var found: usize = 0;
        var bytes: usize = 0;

        var timer = try std.time.Timer.start();

        for (0..LOOPS) |_| {
            fbr.pos = 0;

            while (true) {
                // use as unbuffered reader by setting 'readBuffer = null'
                io.streamUntilDelimiter(
                    &fbr,
                    .{ .readBuffer = null },
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
                out_stream.pos = 0;
            }
        }
        const elapsed = timer.lap();
        std.debug.print(
            "Took: {d}us ({d}ns / iteration) {d} entries, {d} bytes\n",
            .{ elapsed / 1000, elapsed / LOOPS, found, bytes },
        );
    }

    {
        // time std.io stream
        var found: usize = 0;
        var bytes: usize = 0;
        var fbr = std.io.fixedBufferStream(&in);
        var out: [10000]u8 = undefined;
        var out_stream = std.io.fixedBufferStream(&out);

        var timer = try std.time.Timer.start();

        for (0..LOOPS) |_| {
            fbr.pos = 0;

            while (true) {
                fbr.reader().streamUntilDelimiter(
                    out_stream.writer(),
                    '\n',
                    out.len,
                ) catch |err| switch (err) {
                    error.EndOfStream => break,
                    else => return err,
                };

                found += 1;
                bytes += out_stream.getWritten().len;
                out_stream.pos = 0;
            }
        }
        const elapsed = timer.lap();
        std.debug.print(
            "Took: {d}us ({d}ns / iteration) {d} entries, {d} bytes\n",
            .{ elapsed / 1000, elapsed / LOOPS, found, bytes },
        );
    }
}
