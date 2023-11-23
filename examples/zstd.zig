const std = @import("std");

pub const io = @import("io.zig");

test {
    std.testing.refAllDecls(@This());
}
