const std = @import("std");

pub const io = @import("io.zig");
pub const fmt = @import("fmt.zig");

test {
    std.testing.refAllDecls(@This());
}
