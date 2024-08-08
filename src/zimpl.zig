pub const ztable = @import("ztable.zig");

pub fn Impl(comptime Ifc: fn (type) type, comptime T: type) type {
    const U = switch (@typeInfo(T)) {
        .Pointer => |info| if (info.size == .One) info.child else T,
        else => T,
    };
    switch (@typeInfo(U)) {
        .Struct, .Union, .Enum, .Opaque => {},
        else => return Ifc(T),
    }
    var fields = @typeInfo(Ifc(T)).Struct.fields[0..].*;
    for (&fields) |*field| {
        if (@hasDecl(U, field.name)) {
            field.*.default_value = &@as(field.type, @field(U, field.name));
        }
    }
    return @Type(@import("std").builtin.Type{ .Struct = .{
        .layout = .auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

