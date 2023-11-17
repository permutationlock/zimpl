const std = @import("std");

pub fn PtrChild(comptime Type: type) type {
    switch (@typeInfo(Type)) {
        .Pointer => |info| if (info.size == .One) {
            return info.child;
        },
        else => {},
    }
    @compileError(std.fmt.comptimePrint(
        "expected pointer, found '{}'",
        .{ Type }
    ));
}

pub fn Impl(comptime Type: type, comptime Ifc: fn (type) type) type {
    comptime {
        const UWType = Unwrap(Type);
        const impl_decls = getNamespace(Ifc(Type));
        var fields: [impl_decls.len]std.builtin.Type.StructField = undefined;

        var findex: usize = 0;
        for (impl_decls) |decl| {
            const fld_type = @field(Ifc(Type), decl.name);
            var fld = &fields[findex];
            fld.*.name = decl.name;
            fld.*.alignment = 0;    // defualt alignnment
            fld.*.is_comptime = false;
            fld.*.type = switch (@TypeOf(fld_type)) {
                type => fld_type,
                else => @TypeOf(fld_type),
            };
            fld.*.default_value = null;
            if (std.mem.eql(u8, decl.name, "Error")) {
                @compileLog(fld.*.type);
                @compileLog(@TypeOf(fld_type));
            }
            if (fld.*.type == @TypeOf(fld_type)) {
                fld.*.default_value = &fld_type;
            }
            switch (@typeInfo(UWType)) {
                inline else => |info| if (@hasField(@TypeOf(info), "decls")) {
                    if (@hasDecl(UWType, decl.name)) {
                        if (@TypeOf(@field(UWType, decl.name)) == fld.*.type) {
                            fld.*.default_value = &@field(UWType, decl.name);
                        }
                    }
                },
            }

            findex += 1;
        }
        return @Type(std.builtin.Type{
            .Struct = .{
                .layout = .Auto,
                .backing_integer = null,
                .fields = fields[0..findex],
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

fn getDecl(
    comptime Type: type,
    comptime ExpectedType: type,
    comptime decl_name: []const u8
) ?type {
    switch (@typeInfo(Type)) {
        inline else => |info| if (@hasField(@TypeOf(info), "decls")) {
            if (@hasDecl(Unwrap(Type), decl_name)) {
                const decl = @field(Unwrap(Type), decl_name);
                if (@TypeOf(decl) == ExpectedType) {
                    return decl;
                }
            }
        },
    }
    return null;
}

fn getNamespace(comptime Type: type) []const std.builtin.Type.Declaration {
    return switch (@typeInfo(Type)) {
        inline else => |info| if (@hasField(@TypeOf(info), "decls")) info.decls
            else &[0]std.builtin.Type.Declaration{},
    };
}
