const std = @import("std");

pub const IfcFn = fn (comptime type) type;

pub fn Impl(comptime Type: type, comptime args: anytype) type {
    const Ifc: IfcFn = switch (@typeInfo(@TypeOf(args))) {
        .Fn => if (@TypeOf(args) == IfcFn) args else @compileError(
            std.fmt.comptimePrint(
                "expected '{}', found '{}'",
                .{ IfcFn, @TypeOf(args) },
            ),
        ),
        .Struct => |info| blk: {
            var MIfc: ?IfcFn = null;
            for (info.fields) |fld| {
                if (fld.type == IfcFn) {
                    if (MIfc) |Ifc1| {
                        MIfc = Union(Ifc1, @field(args, fld.name));
                    } else {
                        MIfc = @field(args, fld.name);
                    }
                } else {
                    @compileError(std.fmt.comptimePrint(
                        "expected '{}', found '{}'",
                        .{ IfcFn, fld.type },
                    ));
                }
            }
            if (MIfc) |I| {
                break :blk I;
            }
            @compileError(std.fmt.comptimePrint(
                "expected tuple of '{}', found '{}'",
                .{ IfcFn, @TypeOf(args) },
            ));
        },
        else => @compileError(std.fmt.comptimePrint(
            "expected tuple or '{}', found '{}'",
            .{ IfcFn, @TypeOf(args) },
        )),
    };
    const UWType = Unwrap(Type);
    const impl_decls = getNamespace(Ifc(Type));
    var fields: [impl_decls.len]std.builtin.Type.StructField = undefined;

    var fld_index = 0;
    for (impl_decls) |decl| {
        const fld_type = @field(Ifc(Type), decl.name);
        if (@TypeOf(fld_type) != type) {
            @compileError(std.fmt.comptimePrint(
                "non-type declaration '{}.{s}: {}' found in interface'",
                .{ Ifc(Type), decl.name, @TypeOf(fld_type) },
            ));
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

fn Union(comptime Ifc1: IfcFn, comptime Ifc2: IfcFn) IfcFn {
    return struct {
        pub fn Ifc(comptime Type: type) type {
            return struct {
                pub usingnamespace Ifc1(Type);
                pub usingnamespace Ifc2(Type);
            };
        }
    }.Ifc;
}

fn getNamespace(comptime Type: type) []const std.builtin.Type.Declaration {
    return switch (@typeInfo(Type)) {
        inline else => |info| if (@hasField(
            @TypeOf(info),
            "decls",
        )) info.decls else &[0]std.builtin.Type.Declaration{},
    };
}
