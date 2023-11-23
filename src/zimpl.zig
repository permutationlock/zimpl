const std = @import("std");

pub fn Impl(comptime Type: type, comptime Ifc: fn (type) type) type {
    const ifc_fields = @typeInfo(Ifc(Type)).Struct.fields;
    var fields: [ifc_fields.len]std.builtin.Type.StructField = undefined;
    for (&fields, ifc_fields) |*fld, ifc_fld| {
        fld.* = ifc_fld;
        // infer default value from Unwrap(Type)
        const UWType = Unwrap(Type);
        switch (@typeInfo(UWType)) {
            inline else => |info| if (@hasField(@TypeOf(info), "decls")) {
                if (@hasDecl(UWType, ifc_fld.name)) {
                    const decl = @field(UWType, ifc_fld.name);
                    fld.*.default_value = &@as(ifc_fld.type, decl);
                }
            },
        }
    }
    return @Type(std.builtin.Type{
        .Struct = .{
            .layout = .Auto,
            .fields = &fields,
            .decls = &[0]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
}

fn Unwrap(comptime Type: type) type {
    return switch (@typeInfo(Type)) {
        .Pointer => |info| if (info.size == .One) Unwrap(info.child) else Type,
        .Optional => |info| Unwrap(info.child),
        .ErrorUnion => |info| Unwrap(info.payload),
        else => Type,
    };
}
