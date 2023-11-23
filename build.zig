const std = @import("std");
const Builder = std.build.Builder;

const Example = struct { name: []const u8, path: []const u8 };
const paths = [_]Example{
    .{ .name = "count", .path = "examples/count.zig" },
    .{ .name = "iterator", .path = "examples/iterator.zig" },
    .{ .name = "zstd", .path = "examples/zstd.zig" },
    .{ .name = "read_file", .path = "examples/read_file.zig" },
    //    .{ .name = "pointer_cast", .path = "examples/pointer_cast.zig" },
};

pub fn build(b: *Builder) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zimpl = b.addModule("zimpl", .{
        .source_file = .{ .path = "src/zimpl.zig" },
    });

    const test_step = b.step("test", &.{});

    inline for (paths) |example| {
        const t = b.addTest(.{
            .name = example.name,
            .root_source_file = .{ .path = example.path },
            .target = target,
            .optimize = optimize,
        });
        t.addModule("zimpl", zimpl);
        const r = b.addRunArtifact(t);
        test_step.dependOn(&r.step);
    }
}
