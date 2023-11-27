const std = @import("std");
const Impl = @import("zimpl").Impl;
const io = @import("io.zig");

pub fn Serializable(comptime T: type) type {
    return if (AutoSer(T)) |Auto| struct {
        serialze: SerializeFn(T) = Auto.serialize,
        deserialize: DeserializeFn(T) = Auto.deserialize,
    } else struct {
        serialize: SerializeFn(T),
        deserialize: DeserializeFn(T),
    };
}

fn SerializeFn(comptime T: type) type {
    return @TypeOf(struct {
        fn f(
            writer_ctx: anytype,
            writer_impl: Impl(@TypeOf(writer_ctx), io.Writer),
            _: T,
        ) writer_impl.WriteError!void {}
    }.f);
}

fn DeserializeFn(comptime T: type) type {
    return @TypeOf(struct {
        fn f(
            reader_ctx: anytype,
            reader_impl: Impl(@TypeOf(reader_ctx), io.Reader),
        ) (reader_impl.ReadError || error{ BadData, EndOfStream })!T {}
    }.f);
}

fn AutoSer(comptime T: type) ?type {
    return switch (@typeInfo(T)) {
        .Int => struct {
            pub const serialized_size = @sizeOf(T);

            pub fn serialize(
                writer_ctx: anytype,
                writer_impl: Impl(@TypeOf(writer_ctx), io.Writer),
                t: T,
            ) writer_impl.WriteError!void {
                if (T == usize) {
                    try io.writeInt(u64, t);
                }
                try io.writeInt(T, t);
            }

            fn deserialize(
                reader_ctx: anytype,
                reader_impl: Impl(@TypeOf(reader_ctx), io.Reader),
            ) (reader_impl.ReadError || error{ BadData, EndOfStream })!T {
                if (T == usize) {
                    return io.readInt(reader_ctx, reader_impl, u64, .little);
                }
                return io.readInt(reader_ctx, reader_impl, T, .little);
            }
        },
        .Float => if (T == c_longdouble) null else struct {
            pub const serialized_size = @sizeOf(T);

            pub fn serialize(
                writer_ctx: anytype,
                writer_impl: Impl(@TypeOf(writer_ctx), io.Writer),
                t: T,
            ) writer_impl.WriteError!void {
                try io.writeFloat(T, t);
            }

            fn deserialize(
                reader_ctx: anytype,
                reader_impl: Impl(@TypeOf(reader_ctx), io.Reader),
            ) (reader_impl.ReadError || error{ BadData, EndOfStream })!T {
                return io.readFloat(T);
            }
        },
        .Array => |info| if (AutoSer(info.child)) |ElemSer| struct {
            pub const serialized_size = info.len * ElemSer.serialized_size;

            pub fn serialize(
                writer_ctx: anytype,
                writer_impl: Impl(@TypeOf(writer_ctx), io.Writer),
                t: T,
            ) writer_impl.WriteError!void {
                for (t) |elem| {
                    try ElemSer.serialize(writer_ctx, writer_impl, elem);
                }
            }

            pub fn deserialize(
                reader_ctx: anytype,
                reader_impl: Impl(@TypeOf(reader_ctx), io.Reader),
            ) (reader_impl.ReadError || error{ BadData, EndOfStream })!void {
                var t: T = undefined;
                inline for (&t) |elem| {
                    elem = try ElemSer.deserialize(reader_ctx, reader_impl);
                }
                return t;
            }
        } else null,
        .Enum => |info| if (AutoSer(info.tag_type)) |TagSer| struct {
            pub const serialized_size = TagSer.serialized_size;

            pub fn serialize(
                writer_ctx: anytype,
                writer_impl: Impl(@TypeOf(writer_ctx), io.Writer),
                t: T,
            ) writer_impl.WriteError!void {
                try TagSer.serialize(writer_ctx, writer_impl, @intFromEnum(t));
            }

            pub fn deserialize(
                reader_ctx: anytype,
                reader_impl: Impl(@TypeOf(reader_ctx), io.Reader),
            ) (reader_impl.ReadError || error{ BadData, EndOfStream })!void {
                return TagSer.deserialize(reader_ctx, reader_impl);
            }
        } else null,
        .Union => |info| if (info.tag_type) |Tag| blk: {
            if (AutoSer(Tag) == null) break :blk null;
            comptime var body_size: usize = 0;
            inline for (info.fields) |fld| {
                if (AutoSer(fld.type)) |FieldSer| {
                    body_size = @max(body_size, FieldSer.serialized_size);
                } else {
                    break :blk null;
                }
            }
            const tag_size: usize = AutoSer(Tag).?.serialized_size;
            const UnionSer = struct {
                pub const serialized_size = body_size + tag_size;

                pub fn serialize(
                    writer_ctx: anytype,
                    writer_impl: Impl(@TypeOf(writer_ctx), io.Writer),
                    t: T,
                ) writer_impl.WriteError!void {
                    const active_tag: Tag = t;
                    AutoSer(Tag).?.serialize(
                        writer_ctx,
                        writer_impl,
                        active_tag,
                    );
                    inline for (info.fields) |fld| {
                        if (@field(Tag, fld.name) == active_tag) {
                            try AutoSer(fld.type).?.serialize(
                                writer_ctx,
                                writer_impl,
                                @field(t, active_tag),
                            );
                        }
                    }
                }
                pub fn deserialize(
                    reader_ctx: anytype,
                    reader_impl: Impl(@TypeOf(reader_ctx), io.Reader),
                ) (reader_impl.ReadError || error{ BadData, EndOfStream })!void {
                    const active_tag = AutoSer(Tag).?.deserialize(
                        reader_ctx,
                        reader_impl,
                    );
                    inline for (info.fields) |fld| {
                        if (@field(Tag, fld.name) == active_tag) {
                            return @unionInit(
                                T,
                                fld.name,
                                try AutoSer(fld.type).?.deserialize(
                                    reader_ctx,
                                    reader_impl,
                                ),
                            );
                        }
                    }
                    return error.BadData;
                }
            };
            break :blk UnionSer;
        } else null,
        .Optional => |info| if (AutoSer(info.child)) |ChildSer| struct {
            pub const serialized_size = 1 + ChildSer.serialized_size;

            pub fn serialize(
                writer_ctx: anytype,
                writer_impl: Impl(@TypeOf(writer_ctx), io.Writer),
                t: T,
            ) writer_impl.WriteError!void {
                if (t) |child| {
                    try io.writeInt(writer_ctx, writer_impl, u8, 1, .little);
                    try ChildSer.serialize(writer_ctx, writer_impl, child);
                } else {
                    try io.writeInt(writer_ctx, writer_impl, u8, 0, .little);
                }
            }

            pub fn deserialize(
                reader_ctx: anytype,
                reader_impl: Impl(@TypeOf(reader_ctx), io.Reader),
            ) (reader_impl.ReadError || error{ BadData, EndOfStream })!void {
                const is_null = try io.readInt(
                    reader_ctx,
                    reader_impl,
                    u8,
                    .little,
                );
                if (is_null == 1) {
                    return ChildSer.deserialize(reader_ctx, reader_impl);
                } else if (is_null == 0) {
                    return null;
                }
                return error.BadData;
            }
        } else null,
        else => null,
    };
}

pub fn serialize(
    writer_ctx: anytype,
    writer_impl: Impl(@TypeOf(writer_ctx), io.Writer),
    serialize_ctx: anytype,
    serialize_impl: Impl(@TypeOf(serialize_ctx), Serializable),
) writer_impl.WriteError!void {
    _ = serialize_impl;
}

test "serialize int" {}
