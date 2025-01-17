// Wrote this with inspiration from a Karl Seguin article,
// it's just playing around, not to be taken too seriously.

const std = @import("std");
const io = @import("io");
const vio = io.vio;

const LOOPS = 1000;

pub fn main() !void {
    var in: [100000]u8 = undefined;
    try std.posix.getrandom(&in);

    {
        // time buffered generic stream
        var fbr = io.FixedBufferReader{ .buffer = &in };
        var out: [10000]u8 = undefined;
        var out_stream = io.FixedBufferStream{ .buffer = &out };

        var found: usize = 0;
        var bytes: usize = 0;

        asm volatile ("" ::: "memory");
        var timer = try std.time.Timer.start();
        asm volatile ("" ::: "memory");

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

        asm volatile ("" ::: "memory");
        const elapsed = timer.lap();
        asm volatile ("" ::: "memory");

        std.debug.print("buffered zimpl io\n", .{});
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

        asm volatile ("" ::: "memory");
        var timer = try std.time.Timer.start();
        asm volatile ("" ::: "memory");

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

        asm volatile ("" ::: "memory");
        const elapsed = timer.lap();
        asm volatile ("" ::: "memory");

        std.debug.print("unbuffered zimpl io\n", .{});
        std.debug.print(
            "Took: {d}us ({d}ns / iteration) {d} entries, {d} bytes\n",
            .{ elapsed / 1000, elapsed / LOOPS, found, bytes },
        );
    }

    {
        // time virtual buffered generic stream
        var fbr = io.FixedBufferReader{ .buffer = &in };
        var out: [10000]u8 = undefined;
        var out_stream = io.FixedBufferStream{ .buffer = &out };

        const reader = vio.Reader.init(.direct, &fbr, .{});
        const writer = vio.Writer.init(.direct, &out_stream, .{});

        var found: usize = 0;
        var bytes: usize = 0;

        asm volatile ("" ::: "memory");
        var timer = try std.time.Timer.start();
        asm volatile ("" ::: "memory");

        for (0..LOOPS) |_| {
            fbr.pos = 0;

            while (true) {
                vio.streamUntilDelimiter(
                    reader,
                    writer,
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

        asm volatile ("" ::: "memory");
        const elapsed = timer.lap();
        asm volatile ("" ::: "memory");

        std.debug.print("buffered zimpl vio\n", .{});
        std.debug.print(
            "Took: {d}us ({d}ns / iteration) {d} entries, {d} bytes\n",
            .{ elapsed / 1000, elapsed / LOOPS, found, bytes },
        );
    }

    {
        // time virtual unbuffered generic stream
        var fbr = io.FixedBufferReader{ .buffer = &in };
        var out: [10000]u8 = undefined;
        var out_stream = io.FixedBufferStream{ .buffer = &out };

        const reader = vio.Reader.init(.direct, &fbr, .{ .readBuffer = null });
        const writer = vio.Writer.init(.direct, &out_stream, .{});

        var found: usize = 0;
        var bytes: usize = 0;

        asm volatile ("" ::: "memory");
        var timer = try std.time.Timer.start();
        asm volatile ("" ::: "memory");

        for (0..LOOPS) |_| {
            fbr.pos = 0;

            while (true) {
                vio.streamUntilDelimiter(
                    reader,
                    writer,
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

        asm volatile ("" ::: "memory");
        const elapsed = timer.lap();
        asm volatile ("" ::: "memory");

        std.debug.print("unbuffered zimpl vio\n", .{});
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

        const reader = fbr.reader();
        const anyreader = reader.any();
        const writer = out_stream.writer();

        asm volatile ("" ::: "memory");
        var timer = try std.time.Timer.start();
        asm volatile ("" ::: "memory");

        for (0..LOOPS) |_| {
            fbr.pos = 0;

            while (true) {
                anyreader.streamUntilDelimiter(
                    writer,
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

        asm volatile ("" ::: "memory");
        const elapsed = timer.lap();
        asm volatile ("" ::: "memory");

        std.debug.print("std.io fixedBufferStream\n", .{});
        std.debug.print(
            "Took: {d}us ({d}ns / iteration) {d} entries, {d} bytes\n",
            .{ elapsed / 1000, elapsed / LOOPS, found, bytes },
        );
    }

    //{
    //    // time std.io stream
    //    var found: usize = 0;
    //    var bytes: usize = 0;
    //    var fbr = std.io.fixedBufferStream(&in);
    //    var out: [10000]u8 = undefined;
    //    var out_stream = std.io.fixedBufferStream(&out);

    //    var bfbr = std.io.bufferedReader(fbr.reader());
    //    var boutstream = std.io.bufferedWriter(out_stream.writer());

    //    const reader = bfbr.reader();
    //    const anyreader = reader.any();
    //    const writer = boutstream.writer();

    //    var timer = try std.time.Timer.start();

    //    for (0..LOOPS) |_| {
    //        fbr.pos = 0;

    //        while (true) {
    //            anyreader.streamUntilDelimiter(
    //                writer,
    //                '\n',
    //                out.len,
    //            ) catch |err| switch (err) {
    //                error.EndOfStream => break,
    //                else => return err,
    //            };

    //            try boutstream.flush();
    //            found += 1;
    //            bytes += out_stream.getWritten().len;
    //            out_stream.pos = 0;
    //        }
    //    }
    //    const elapsed = timer.lap();
    //    std.debug.print("buffered std.io fixedBufferStream\n", .{});
    //    std.debug.print(
    //        "Took: {d}us ({d}ns / iteration) {d} entries, {d} bytes\n",
    //        .{ elapsed / 1000, elapsed / LOOPS, found, bytes },
    //    );
    //}
}
