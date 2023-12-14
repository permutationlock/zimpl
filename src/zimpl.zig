const Type = @import("std").builtin.Type;

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
        .layout = .Auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

pub fn VIfc(comptime Ifc: fn (type) type) type {
    return struct {
        ctx: *anyopaque,
        vtable: VTable(Ifc),
    };
}

pub const CtxAccess = enum { Direct, Indirect };

pub fn makeVIfc(
    comptime Ifc: fn (type) type,
    comptime access: CtxAccess,
) fn (anytype, anytype) VIfc(Ifc) {
    return struct {
        fn f(
            ctx: anytype,
            impl: Impl(Ifc, CtxType(@TypeOf(ctx), access)),
        ) VIfc(Ifc) {
            return .{
                .ctx = if (access == .Indirect) @constCast(ctx) else ctx,
                .vtable = vtable(Ifc, @TypeOf(ctx), access, impl),
            };
        }
    }.f;
}

fn CtxType(comptime Ctx: type, comptime access: CtxAccess) type {
    return if (access == .Indirect) PtrChild(Ctx) else Ctx;
}

fn VTable(comptime Ifc: fn (type) type) type {
    const ifc_fields = @typeInfo(Ifc(*anyopaque)).Struct.fields;
    var fields: [ifc_fields.len]Type.StructField = undefined;
    var i: usize = 0;
    for (ifc_fields) |*field| {
        switch (@typeInfo(field.type)) {
            .Optional => |info| {
                fields[i] = .{
                    .name = field.name,
                    .type = ?*const info.child,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = 0,
                };
                i += 1;
            },
            .Fn => {
                fields[i] = .{
                    .name = field.name,
                    .type = *const field.type,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = 0,
                };
                i += 1;
            },
            else => {},
        }
    }
    return @Type(Type{ .Struct = .{
        .layout = .Auto,
        .fields = fields[0..i],
        .decls = &.{},
        .is_tuple = false,
    } });
}

fn PtrChild(comptime Ptr: type) type {
    return switch (@typeInfo(Ptr)) {
        .Pointer => |info| if (info.size == .One)
            info.child
        else
            @compileError("expected single item pointer"),
        else => @compileError("expected single item pointer"),
    };
}

fn vtable(
    comptime Ifc: fn (type) type,
    comptime Ctx: type,
    comptime access: CtxAccess,
    comptime impl: Impl(Ifc, CtxType(Ctx, access)),
) VTable(Ifc) {
    var vt: VTable(Ifc) = undefined;
    inline for (@typeInfo(VTable(Ifc)).Struct.fields) |fld_info| {
        const impl_func = @field(impl, fld_info.name);
        @field(vt, fld_info.name) = switch (@typeInfo(fld_info.type)) {
            .Optional => |opt| if (impl_func) |func| &virtualize(
                @typeInfo(opt.child).Pointer.child,
                Ctx,
                access,
                func,
            ) else null,
            else => &virtualize(
                @typeInfo(fld_info.type).Pointer.child,
                Ctx,
                access,
                impl_func,
            ),
        };
    }
    return vt;
}

fn virtualize(
    comptime VFn: type,
    comptime Ctx: type,
    comptime access: CtxAccess,
    comptime func: anytype,
) VFn {
    const params = @typeInfo(@TypeOf(func)).Fn.params;
    const return_type = @typeInfo(VFn).Fn.return_type.?;
    const Self = if (access == .Indirect) PtrChild(Ctx) else Ctx;

    if (params.len == 0 or params[0].type.? != Self) {
        return func;
    }
    return switch (params.len) {
        1 => struct {
            fn impl(self: *anyopaque) return_type {
                return func(castCtx(Self, access, self));
            }
        }.impl,
        2 => struct {
            fn impl(self: *anyopaque, p1: params[1].type.?) return_type {
                return func(castCtx(Self, access, self), p1);
            }
        }.impl,
        3 => struct {
            fn impl(
                self: *anyopaque,
                p1: params[1].type.?,
                p2: params[2].type.?,
            ) return_type {
                return func(castCtx(Self, access, self), p1, p2);
            }
        }.impl,
        4 => struct {
            fn impl(
                self: *anyopaque,
                p1: params[1].type.?,
                p2: params[2].type.?,
                p3: params[3].type.?,
            ) return_type {
                return func(castCtx(Self, access, self), p1, p2, p3);
            }
        }.impl,
        5 => struct {
            fn impl(
                self: *anyopaque,
                p1: params[1].type.?,
                p2: params[2].type.?,
                p3: params[3].type.?,
                p4: params[4].type.?,
            ) return_type {
                return func(castCtx(Self, access, self), p1, p2, p3, p4);
            }
        }.impl,
        6 => struct {
            fn impl(
                self: *anyopaque,
                p1: params[1].type.?,
                p2: params[2].type.?,
                p3: params[3].type.?,
                p4: params[4].type.?,
                p5: params[5].type.?,
            ) return_type {
                return func(castCtx(Self, access, self), p1, p2, p3, p4, p5);
            }
        }.impl,
        else => {
            @compileError("cannot virtualize member functions with >6 params");
        },
    };
}

fn castCtx(
    comptime Ctx: type,
    comptime access: CtxAccess,
    ptr: *anyopaque,
) Ctx {
    return if (access == .Indirect)
        @as(*Ctx, @alignCast(@ptrCast(ptr))).*
    else
        @alignCast(@ptrCast(ptr));
}
