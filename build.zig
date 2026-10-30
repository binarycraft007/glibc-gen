const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const arch_opt = b.option(
        []const u8,
        "arch",
        "Target glibc architecture to generate files for, or 'all' (default: all)",
    ) orelse "all";
    const out_dir_opt = b.option(
        []const u8,
        "out-dir",
        "Output directory for generated glibc files (default: zig-out/generated)",
    ) orelse "zig-out/generated";

    const exe = b.addExecutable(.{
        .name = "glibc-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the glibc generator");
    const gen_step = b.step("gen", "Generate glibc headers (.h), sources (.c), assembly (.S), and linker scripts (.map)");
    const list_step = b.step("list-archs", "List all Zig-supported glibc architectures");

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.addArg(b.fmt("--arch={s}", .{arch_opt}));
    run_cmd.addArg(b.fmt("--out-dir={s}", .{out_dir_opt}));
    run_step.dependOn(&run_cmd.step);
    gen_step.dependOn(&run_cmd.step);

    const list_cmd = b.addRunArtifact(exe);
    list_cmd.addArg("--list-archs");
    list_step.dependOn(&list_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.addPassthruArgs();

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
