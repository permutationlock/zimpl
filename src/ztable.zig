const Type = @import("std").builtin.Type;

const zimpl = @import("zimpl.zig");
const Impl = zimpl.Impl;

pub const CtxAccess = enum { direct, indirect };

pub fn VIfc(comptime Ifc: fn (type) type) type {
    return struct {
        ctx: *anyopaque,
        vtable: VTable(Ifc),

        pub fn init(
            comptime access: CtxAccess,
            ctx: anytype,
            impl: Impl(Ifc, CtxType(@TypeOf(ctx), access)),
        ) @This() {
            return .{
                .ctx = if (access == .indirect) @constCast(ctx) else ctx,
                .vtable = vtable(Ifc, access, @TypeOf(ctx), impl),
            };
        }
    };
}

pub fn VTable(comptime Ifc: fn (type) type) type {
    const ifc_fields = @typeInfo(Ifc(*anyopaque)).@"struct".fields;
    var fields: [ifc_fields.len]Type.StructField = undefined;
    var i: usize = 0;
    for (ifc_fields) |*field| {
        switch (@typeInfo(field.type)) {
            .optional => |info| if (@typeInfo(info.child) == .@"fn") {
                fields[i] = .{
                    .name = field.name,
                    .type = ?*const info.child,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = 0,
                };
                i += 1;
            },
            .@"fn" => {
                fields[i] = .{
                    .name = field.name,
                    .type = *const field.type,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = 0,
                };
                i += 1;
            },
            else => {},
        }
    }
    return @Type(Type{ .@"struct" = .{
        .layout = .auto,
        .fields = fields[0..i],
        .decls = &.{},
        .is_tuple = false,
    } });
}

pub fn vtable(
    comptime Ifc: fn (type) type,
    comptime access: CtxAccess,
    comptime Ctx: type,
    comptime impl: Impl(Ifc, CtxType(Ctx, access)),
) VTable(Ifc) {
    var vt: VTable(Ifc) = undefined;
    inline for (@typeInfo(VTable(Ifc)).@"struct".fields) |fld_info| {
        const impl_func = @field(impl, fld_info.name);
        @field(vt, fld_info.name) = switch (@typeInfo(fld_info.type)) {
            .optional => |opt| if (impl_func) |func| &virtualize(
                @typeInfo(opt.child).pointer.child,
                access,
                Ctx,
                func,
            ) else null,
            else => &virtualize(
                @typeInfo(fld_info.type).pointer.child,
                access,
                Ctx,
                impl_func,
            ),
        };
    }
    return vt;
}

fn CtxType(comptime Ctx: type, comptime access: CtxAccess) type {
    return if (access == .indirect) @typeInfo(Ctx).pointer.child else Ctx;
}

fn virtualize(
    comptime VFn: type,
    comptime access: CtxAccess,
    comptime Ctx: type,
    comptime func: anytype,
) VFn {
    const params = @typeInfo(@TypeOf(func)).@"fn".params;
    const return_type = @typeInfo(VFn).@"fn".return_type.?;

    return switch (params.len) {
        0 => func,
        1 => struct {
            fn impl(ctx: *anyopaque) return_type {
                return func(castCtx(access, Ctx, ctx));
            }
        }.impl,
        2 => struct {
            fn impl(ctx: *anyopaque, p1: params[1].type.?) return_type {
                return func(castCtx(access, Ctx, ctx), p1);
            }
        }.impl,
        3 => struct {
            fn impl(
                ctx: *anyopaque,
                p1: params[1].type.?,
                p2: params[2].type.?,
            ) return_type {
                return func(castCtx(access, Ctx, ctx), p1, p2);
            }
        }.impl,
        4 => struct {
            fn impl(
                ctx: *anyopaque,
                p1: params[1].type.?,
                p2: params[2].type.?,
                p3: params[3].type.?,
            ) return_type {
                return func(castCtx(access, Ctx, ctx), p1, p2, p3);
            }
        }.impl,
        5 => struct {
            fn impl(
                ctx: *anyopaque,
                p1: params[1].type.?,
                p2: params[2].type.?,
                p3: params[3].type.?,
                p4: params[4].type.?,
            ) return_type {
                return func(castCtx(access, Ctx, ctx), p1, p2, p3, p4);
            }
        }.impl,
        6 => struct {
            fn impl(
                ctx: *anyopaque,
                p1: params[1].type.?,
                p2: params[2].type.?,
                p3: params[3].type.?,
                p4: params[4].type.?,
                p5: params[5].type.?,
            ) return_type {
                return func(castCtx(access, Ctx, ctx), p1, p2, p3, p4, p5);
            }
        }.impl,
        7 => struct {
            fn impl(
                ctx: *anyopaque,
                p1: params[1].type.?,
                p2: params[2].type.?,
                p3: params[3].type.?,
                p4: params[4].type.?,
                p5: params[5].type.?,
                p6: params[6].type.?,
            ) return_type {
                return func(castCtx(access, Ctx, ctx), p1, p2, p3, p4, p5, p6);
            }
        }.impl,
        else => {
            @compileError("can't virtualize member function: too many params");
        },
    };
}

inline fn castCtx(
    comptime access: CtxAccess,
    comptime Ctx: type,
    ptr: *anyopaque,
) CtxType(Ctx, access) {
    return if (access == .indirect)
        @as(*const CtxType(Ctx, access), @alignCast(@ptrCast(ptr))).*
    else
        @alignCast(@ptrCast(ptr));
}
