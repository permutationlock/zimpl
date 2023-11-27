pub fn Unwrap(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .Pointer => |info| if (info.size == .One) Unwrap(info.child) else T,
        .Optional => |info| Unwrap(info.child),
        .ErrorUnion => |info| Unwrap(info.payload),
        else => T,
    };
}
