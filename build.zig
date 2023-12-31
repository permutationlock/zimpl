const std = @import("std");
const Builder = std.build.Builder;

const BuildFile = struct {
    name: []const u8,
    path: []const u8,
    deps: []const Builder.ModuleDependency = &.{},
};

pub fn build(b: *Builder) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zimpl = b.addModule("zimpl", .{
        .source_file = .{ .path = "src/zimpl.zig" },
    });

    const examples = [_]BuildFile{
        .{ .name = "count", .path = "examples/count.zig" },
        .{ .name = "iterator", .path = "examples/iterator.zig" },
        .{ .name = "io", .path = "examples/io.zig" },
        .{ .name = "read_file", .path = "examples/read_file.zig" },
        .{ .name = "vcount", .path = "examples/vcount.zig" },
        .{ .name = "vcount2", .path = "examples/vcount2.zig" },
    };

    const test_step = b.step("test", &.{});

    inline for (examples) |example| {
        const ex_test = b.addTest(.{
            .name = example.name,
            .root_source_file = .{ .path = example.path },
            .target = target,
            .optimize = optimize,
        });
        ex_test.addModule("zimpl", zimpl);
        for (example.deps) |dep| {
            ex_test.addModule(dep.name, dep.module);
        }
        const run = b.addRunArtifact(ex_test);
        test_step.dependOn(&run.step);
    }

    const io = b.addModule("io", .{
        .source_file = .{
            .path = "examples/io.zig",
        },
        .dependencies = &.{.{ .name = "zimpl", .module = zimpl }},
    });

    const benchmarks = [_]BuildFile{.{
        .name = "buffered_io",
        .path = "benchmarks/buffered_io.zig",
        .deps = &.{.{ .name = "io", .module = io }},
    }};

    const benchmark_step = b.step("benchmark", &.{});

    inline for (benchmarks) |benchmark| {
        const bench = b.addExecutable(.{
            .name = benchmark.name,
            .root_source_file = .{ .path = benchmark.path },
            .target = target,
            .optimize = .ReleaseFast,
        });
        for (benchmark.deps) |dep| {
            bench.addModule(dep.name, dep.module);
        }
        const run = b.addRunArtifact(bench);
        benchmark_step.dependOn(&run.step);
    }
}
