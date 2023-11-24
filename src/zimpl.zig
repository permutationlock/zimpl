const Type = @import("std").builtin.Type;

pub fn Impl(comptime T: type, comptime Ifc: fn (type) type) type {
    const ifc = @typeInfo(Ifc(T)).Struct.fields;
    var fields = @as(*const [ifc.len]Type.StructField, @ptrCast(ifc.ptr)).*;
    for (&fields) |*field| {
        switch (@typeInfo(Unwrap(T))) {
            inline else => |info| if (@hasField(@TypeOf(info), "decls")) {
                if (@hasDecl(Unwrap(T), field.name)) {
                    const decl = @field(Unwrap(T), field.name);
                    field.*.default_value = &@as(field.type, decl);
                }
            },
        }
    }
    return @Type(Type{ .Struct = .{
        .layout = .Auto,
        .fields = &fields,
        .decls = &[0]Type.Declaration{},
        .is_tuple = false,
    } });
}

fn Unwrap(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .Pointer => |info| if (info.size == .One) Unwrap(info.child) else T,
        .Optional => |info| Unwrap(info.child),
        .ErrorUnion => |info| Unwrap(info.payload),
        else => T,
    };
}
