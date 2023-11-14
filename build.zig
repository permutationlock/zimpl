const std = @import("std");
const Builder = std.build.Builder;

const Example = struct { name: []const u8, path: []const u8 };
const paths = [_]Example{
    .{ .name = "count", .path = "examples/count.zig" },
};

pub fn build(b: *Builder) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zimpl = b.addModule("zimpl", .{
        .source_file = .{ .path = "src/zimpl.zig" },
    });

    inline for (paths) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_source_file = .{ .path = example.path },
            .target = target,
            .optimize = optimize
        });
        exe.addModule("zimpl", zimpl);
        const run_step = b.step(example.name, &.{});
        run_step.dependOn(&b.addRunArtifact(exe).step);
    }
}
