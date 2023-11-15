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
        const impl_decls = getNamespace(Ifc(Type));
        var fields: [impl_decls.len]std.builtin.Type.StructField = undefined;

        var findex: usize = 0;
        for (impl_decls) |decl| {
            const fld_type = @field(Ifc(Type), decl.name);
            if (@TypeOf(fld_type) != type) {
                continue;
            }
            var fld = &fields[findex];
            fld.*.name = decl.name;
            fld.*.alignment = 0;    // defualt alignnment
            fld.*.is_comptime = false;
            fld.*.type = fld_type;
            fld.*.default_value = null;
            switch (@typeInfo(Type)) {
                inline else => |info| if (@hasField(@TypeOf(info), "decls")) {
                    if (@hasDecl(Type, decl.name)) {
                        if (@TypeOf(@field(Type, decl.name)) == fld.*.type) {
                            fld.*.default_value = &@field(Type, decl.name);
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

fn getNamespace(comptime Type: type) []const std.builtin.Type.Declaration {
    return switch (@typeInfo(Type)) {
        inline else => |info| if (@hasField(@TypeOf(info), "decls")) info.decls
            else &[0]std.builtin.Type.Declaration{},
    };
}
