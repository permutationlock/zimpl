const std = @import("std");
const Build = std.Build;
const Import = Build.Module.Import;

const BuildFile = struct {
    name: []const u8,
    path: []const u8,
    imports: []const Import = &.{},
};

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zimpl = b.addModule("zimpl", .{
        .root_source_file = .{ .path = "src/zimpl.zig" },
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
        ex_test.root_module.addImport("zimpl", zimpl);
        for (example.imports) |dep| {
            ex_test.root_moduel.addImport(dep.name, dep.module);
        }
        const run = b.addRunArtifact(ex_test);
        test_step.dependOn(&run.step);
    }

    const io = b.addModule("io", .{
        .root_source_file = .{
            .path = "examples/io.zig",
        },
        .imports = &.{.{ .name = "zimpl", .module = zimpl }},
    });

    const benchmarks = [_]BuildFile{.{
        .name = "buffered_io",
        .path = "benchmarks/buffered_io.zig",
        .imports = &.{.{ .name = "io", .module = io }},
    }};

    const benchmark_step = b.step("benchmark", &.{});

    inline for (benchmarks) |benchmark| {
        const bench = b.addExecutable(.{
            .name = benchmark.name,
            .root_source_file = .{ .path = benchmark.path },
            .target = target,
            .optimize = .ReleaseFast,
        });
        for (benchmark.imports) |dep| {
            bench.root_module.addImport(dep.name, dep.module);
        }
        const install = b.addInstallArtifact(bench, .{});
        benchmark_step.dependOn(&install.step);
    }
}
