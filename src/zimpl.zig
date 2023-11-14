const std = @import("std");

pub fn Impl(comptime Type: type, comptime Ifc: fn (type) type) type {
    comptime {
        const UWType = Unwrap(Type);
        const impl_decls = getNamespace(Ifc(UWType));
        var fields: [impl_decls.len]std.builtin.Type.StructField = undefined;

        for (&fields, impl_decls) |*fld, decl| {
            const fld_type = @field(Ifc(UWType), decl.name);
            if (@typeInfo(@TypeOf(fld_type)) != .Type) {
                continue;
            }
            fld.*.name = decl.name;
            fld.*.alignment = 0;    // defualt alignnment
            fld.*.is_comptime = false;
            fld.*.type = fld_type;
            fld.*.default_value = null;
            switch (@typeInfo(UWType)) {
                inline else => |info| if (@hasField(@TypeOf(info), "decls")) {
                    if (@hasDecl(UWType, decl.name)) {
                        if (@TypeOf(@field(UWType, decl.name)) == fld.*.type) {
                            fld.*.default_value = &@field(UWType, decl.name);
                        }
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
}

fn Unwrap(comptime Type: type) type {
    return switch (@typeInfo(Type)) {
        .Pointer => |info| if (info.size == .One) info.child else Type,
        else => Type,
    };
}

fn getNamespace(comptime Type: type) []const std.builtin.Type.Declaration {
    return switch (@typeInfo(Type)) {
        inline else => |info| if (@hasField(@TypeOf(info), "decls")) info.decls
            else &[0]std.builtin.Type.Declaration{},
    };
}
