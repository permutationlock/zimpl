const std = @import("std");

pub fn Impl(comptime Type: type, comptime Ifc: fn (type) type) type {
    comptime {
        const UWType = Unwrap(Type);
        const impl_decls = getNamespace(Ifc(Type));
        var fields: [impl_decls.len]std.builtin.Type.StructField = undefined;

        var fld_index = 0;
        for (impl_decls) |decl| {
            const fld_type = @field(Ifc(Type), decl.name);
            if (@TypeOf(fld_type) != type) {
                continue;
            }
            const fld = &fields[fld_index];
            fld.*.name = decl.name;
            fld.*.alignment = 0; // defualt alignnment
            fld.*.is_comptime = false;
            fld.*.type = fld_type;
            fld.*.default_value = null;
            // infer default value from Unwrap(Type)
            switch (@typeInfo(UWType)) {
                inline else => |info| if (@hasField(
                    @TypeOf(info),
                    "decls",
                )) {
                    if (@hasDecl(UWType, decl.name)) {
                        if (@TypeOf(@field(
                            UWType,
                            decl.name,
                        )) == fld.*.type) {
                            fld.*.default_value = &@field(
                                UWType,
                                decl.name,
                            );
                        }
                    }
                },
            }
            fld_index += 1;
        }
        return @Type(std.builtin.Type{
            .Struct = .{
                .layout = .Auto,
                .backing_integer = null,
                .fields = fields[0..fld_index],
                .decls = &[0]std.builtin.Type.Declaration{},
                .is_tuple = false,
            },
        });
    }
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
