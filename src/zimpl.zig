pub const ztable = @import("ztable.zig");

pub fn Impl(comptime Ifc: fn (type) type, comptime T: type) type {
    const U = switch (@typeInfo(T)) {
        .@"pointer" => |info| if (info.size == .one) info.child else T,
        else => T,
    };
    switch (@typeInfo(U)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => {},
        else => return Ifc(T),
    }
    var fields = @typeInfo(Ifc(T)).@"struct".fields[0..].*;
    for (&fields) |*field| {
        if (@hasDecl(U, field.name)) {
            field.*.default_value_ptr = &@as(field.type, @field(U, field.name));
        }
    }
    return @Type(@import("std").builtin.Type{ .@"struct" = .{
        .layout = .auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

