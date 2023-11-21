const std = @import("std");

pub const IfcFn = fn (comptime type) type;

pub fn Impl(comptime Type: type, comptime Ifc: IfcFn) type {
    const impl_decls = getNamespace(Ifc(Type));
    var fields: [impl_decls.len]std.builtin.Type.StructField = undefined;
    for (&fields, impl_decls) |*fld, decl| {
        const fld_type = @field(Ifc(Type), decl.name);
        if (@TypeOf(fld_type) != type) {
            @compileError(std.fmt.comptimePrint(
                "non-type declaration '{}.{s}: {}' not allowed in interface'",
                .{ Ifc(Type), decl.name, @TypeOf(fld_type) },
            ));
        }
        fld.*.name = decl.name;
        fld.*.alignment = 0; // defualt alignnment
        fld.*.is_comptime = false;
        fld.*.type = fld_type;
        fld.*.default_value = null;
        // infer default value from Unwrap(Type)
        const UWType = Unwrap(Type);
        switch (@typeInfo(UWType)) {
            inline else => |info| if (@hasField(@TypeOf(info), "decls")) {
                if (@hasDecl(UWType, decl.name)) {
                    fld.*.default_value = &@as(fld_type, @field(
                        UWType,
                        decl.name,
                    ));
                }
            },
        }
    }
    return @Type(std.builtin.Type{
        .Struct = .{
            .layout = .Auto,
            .backing_integer = null,
            .fields = &fields,
            .decls = &[0]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
}

pub fn Unwrap(comptime Type: type) type {
    return switch (@typeInfo(Type)) {
        .Pointer => |info| if (info.size == .One) Unwrap(info.child) else Type,
        .Optional => |info| Unwrap(info.child),
        .ErrorUnion => |info| Unwrap(info.payload),
        else => Type,
    };
}

pub fn PtrChild(comptime Type: type) type {
    switch (@typeInfo(Type)) {
        .Pointer => |info| if (info.size == .One) {
            return info.child;
        },
        else => {},
    }
    @compileError(std.fmt.comptimePrint("expected pointer, found '{}'", .{Type}));
}

fn getNamespace(comptime Type: type) []const std.builtin.Type.Declaration {
    return switch (@typeInfo(Type)) {
        inline else => |info| if (@hasField(
            @TypeOf(info),
            "decls",
        )) info.decls else &[0]std.builtin.Type.Declaration{},
    };
}
