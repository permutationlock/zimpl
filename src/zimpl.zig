const std = @import("std");

pub const IfcFn = *const fn (type) Interface;

pub fn Impl(comptime Type: type, comptime args: anytype) type {
    comptime {
        const UWType = Unwrap(Type);
        const Ifc: IfcFn = blk: {
            switch (@typeInfo(@TypeOf(args))) {
                .Struct => |tuple_info| {
                    const fields = tuple_info.fields;
                    var ifc_array: [fields.len]IfcFn = undefined;
                    inline for (fields, ifc_array[0..fields.len]) |fld, *tFn| {
                        tFn.* = @field(args, fld.name);
                    }
                    break :blk Join(null, &ifc_array);
                },
                else => break :blk args,
            }
        };
        const req_decls = getNamespace(Ifc(Type).requires);
        const use_decls = getNamespace(Ifc(Type).using);
        const max_fields = req_decls.len + use_decls.len;
        var fields: [max_fields]std.builtin.Type.StructField = undefined;

        var findex: usize = 0;
        for (req_decls) |decl| {
            const fld_type = @field(Ifc(Type).requires, decl.name);
            if (@TypeOf(fld_type) != type) {
                continue;
            }
            var fld = &fields[findex];
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

            findex += 1;
        }
        for (use_decls) |decl| {
            const fld_val = @field(Ifc(Type).using, decl.name);
            var fld = &fields[findex];
            fld.*.name = decl.name;
            fld.*.alignment = 0;    // defualt alignnment
            fld.*.is_comptime = false;
            fld.*.type = @TypeOf(fld_val);
            fld.*.default_value = &fld_val;

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

pub const Interface = struct {
    requires: type = struct {},
    using: type = struct {},
};

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
    @compileError(std.fmt.comptimePrint(
        "expected pointer, found '{}'",
        .{ Type }
    ));
}

pub fn optionals(
    comptime Type: type,
    comptime Defaults: type,
) Optionals(Type, Defaults) {
    return .{};
}

fn Optionals(comptime Type: type, comptime Defaults: type) type {
    comptime {
        const UWType = Unwrap(Type);
        const def_decls = getNamespace(Defaults);
        var fields: [def_decls.len]std.builtin.Type.StructField = undefined;
        for (def_decls, &fields) |decl, *fld| {
            const default = @field(Defaults, decl.name);
            fld.*.name = decl.name;
            fld.*.alignment = 0;    // defualt alignnment
            fld.*.is_comptime = true;
            fld.*.type = @TypeOf(default);
            fld.*.default_value = &default;
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

pub fn Union(Ifc1: IfcFn, Ifc2: IfcFn) IfcFn {
    return struct {
        pub fn U (comptime Type: type) Interface {
            return .{
                .requires = struct {
                    pub usingnamespace Ifc1(Type).requires;
                    pub usingnamespace Ifc2(Type).requires;
                },
                .using = struct {
                    pub usingnamespace Ifc1(Type).using;
                    pub usingnamespace Ifc2(Type).using;
                },
            };
        }
    }.U;
}

fn getNamespace(comptime Type: type) []const std.builtin.Type.Declaration {
    return switch (@typeInfo(Type)) {
        inline else => |info| if (@hasField(@TypeOf(info), "decls")) info.decls
            else &[0]std.builtin.Type.Declaration{},
    };
}

fn Join(
    comptime MIfc: ?IfcFn,
    comptime ifcs: []const IfcFn,
) IfcFn {
    if (MIfc) |Ifc| {
        if (ifcs.len == 0) {
            return Ifc;
        }
        return Join(Union(Ifc, ifcs[0]), ifcs[1..]);
    } else if (ifcs.len == 0) {
        return struct { fn E(comptime _: type) Interface { return .{}; } }.E;
    }
    return Join(ifcs[0], ifcs[1..]);
}
