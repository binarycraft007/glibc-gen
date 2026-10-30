const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const AbiVariant = struct {
    name: []const u8,
    condition: []const u8,
};

pub const ConfigDefine = struct {
    name: []const u8,
    value: []const u8,
};

pub const ArchConfig = struct {
    /// Short CLI name for the architecture (e.g. "x86_64", "aarch64", "riscv64").
    name: []const u8,
    /// glibc base_machine (e.g. "x86_64", "i386", "aarch64", "riscv", "powerpc").
    base_machine: []const u8,
    /// glibc machine path under sysdeps (e.g. "x86_64/64", "arm/le/armv7", "riscv/rv64/rvd").
    machine: []const u8,
    /// GNU config triple used by shlib-versions and scripts/soversions.awk.
    config_triple: []const u8,
    /// Zig target triple passed to `zig cc -target <zig_target>`.
    zig_target: []const u8,
    /// Extra C compiler flags if needed for `zig cc`.
    extra_cflags: []const []const u8 = &.{},
    /// Whether hardware floating point is enabled (`with_fp`).
    with_fp: bool = true,
    /// Default ABI variant name (`default-abi`).
    default_abi: []const u8,
    /// All ABI variants for multilib headers (`gnu/lib-names.h`, `gnu/stubs.h`).
    abi_variants: []const AbiVariant,
    /// Optional header to include in `gnu/lib-names.h` and `gnu/stubs.h` (defaults to "bits/wordsize.h" per Makeconfig).
    abi_include: ?[]const u8 = "bits/wordsize.h",
    /// Shared library directory (`slibdir`) for runtime-linker.h and trusted-dirs.h.
    slibdir: []const u8,
    /// Minimum Linux kernel version (major, minor, sublevel).
    min_kernel: [3]u32,
    /// Whether this target is 64-bit.
    is_64bit: bool,
    /// Architecture-specific config.h defines.
    config_defines: []const ConfigDefine = &.{},
};

pub const x86_abi_variants = [_]AbiVariant{
    .{ .name = "32", .condition = "!defined __x86_64__" },
    .{ .name = "64", .condition = "defined __x86_64__ && defined __LP64__" },
    .{ .name = "x32", .condition = "defined __x86_64__ && defined __ILP32__" },
};

pub const aarch64_abi_variants = [_]AbiVariant{
    .{ .name = "lp64", .condition = "!defined __AARCH64EB__" },
    .{ .name = "lp64_be", .condition = "defined __AARCH64EB__" },
};

pub const arm_abi_variants = [_]AbiVariant{
    .{ .name = "soft", .condition = "!defined __ARM_PCS_VFP" },
    .{ .name = "hard", .condition = "defined __ARM_PCS_VFP" },
};

pub const riscv_abi_variants = [_]AbiVariant{
    .{ .name = "ilp32", .condition = "__WORDSIZE == 32 && defined __riscv_float_abi_soft" },
    .{ .name = "ilp32d", .condition = "__WORDSIZE == 32 && defined __riscv_float_abi_double" },
    .{ .name = "lp64", .condition = "__WORDSIZE == 64 && defined __riscv_float_abi_soft" },
    .{ .name = "lp64d", .condition = "__WORDSIZE == 64 && defined __riscv_float_abi_double" },
};

pub const powerpc_abi_variants = [_]AbiVariant{
    .{ .name = "32", .condition = "__WORDSIZE == 32" },
    .{ .name = "64-v1", .condition = "__WORDSIZE == 64 && _CALL_ELF != 2" },
    .{ .name = "64-v2", .condition = "__WORDSIZE == 64 && _CALL_ELF == 2" },
};

pub const loongarch_abi_variants = [_]AbiVariant{
    .{ .name = "ilp32s", .condition = "__WORDSIZE == 32 && defined __loongarch_soft_float" },
    .{ .name = "ilp32d", .condition = "__WORDSIZE == 32 && defined __loongarch_double_float" },
    .{ .name = "lp64s", .condition = "__WORDSIZE == 64 && defined __loongarch_soft_float" },
    .{ .name = "lp64d", .condition = "__WORDSIZE == 64 && defined __loongarch_double_float" },
};

pub const mips_abi_variants = [_]AbiVariant{
    .{ .name = "o32_soft", .condition = "!defined(__mips_nan2008) && defined(__mips_soft_float) && (_MIPS_SIM == _MIPS_SIM_ABI32)" },
    .{ .name = "o32_hard", .condition = "!defined(__mips_nan2008) && defined(__mips_hard_float) && (_MIPS_SIM == _MIPS_SIM_ABI32)" },
    .{ .name = "o32_soft_2008", .condition = "defined(__mips_nan2008) && defined(__mips_soft_float) && (_MIPS_SIM == _MIPS_SIM_ABI32)" },
    .{ .name = "o32_hard_2008", .condition = "defined(__mips_nan2008) && defined(__mips_hard_float) && (_MIPS_SIM == _MIPS_SIM_ABI32)" },
    .{ .name = "n32_soft", .condition = "!defined(__mips_nan2008) && defined(__mips_soft_float) && (_MIPS_SIM == _MIPS_SIM_NABI32)" },
    .{ .name = "n32_hard", .condition = "!defined(__mips_nan2008) && defined(__mips_hard_float) && (_MIPS_SIM == _MIPS_SIM_NABI32)" },
    .{ .name = "n32_soft_2008", .condition = "defined(__mips_nan2008) && defined(__mips_soft_float) && (_MIPS_SIM == _MIPS_SIM_NABI32)" },
    .{ .name = "n32_hard_2008", .condition = "defined(__mips_nan2008) && defined(__mips_hard_float) && (_MIPS_SIM == _MIPS_SIM_NABI32)" },
    .{ .name = "n64_soft", .condition = "!defined(__mips_nan2008) && defined(__mips_soft_float) && (_MIPS_SIM == _MIPS_SIM_ABI64)" },
    .{ .name = "n64_hard", .condition = "!defined(__mips_nan2008) && defined(__mips_hard_float) && (_MIPS_SIM == _MIPS_SIM_ABI64)" },
    .{ .name = "n64_soft_2008", .condition = "defined(__mips_nan2008) && defined(__mips_soft_float) && (_MIPS_SIM == _MIPS_SIM_ABI64)" },
    .{ .name = "n64_hard_2008", .condition = "defined(__mips_nan2008) && defined(__mips_hard_float) && (_MIPS_SIM == _MIPS_SIM_ABI64)" },
};

pub const sparc_abi_variants = [_]AbiVariant{
    .{ .name = "32", .condition = "__WORDSIZE == 32" },
    .{ .name = "64", .condition = "__WORDSIZE == 64" },
};

pub const supported_archs = [_]ArchConfig{
    .{
        .name = "x86_64",
        .base_machine = "x86_64",
        .machine = "x86_64/64",
        .config_triple = "x86_64-pc-linux-gnu",
        .zig_target = "x86_64-linux-gnu",
        .default_abi = "64",
        .abi_variants = &x86_abi_variants,
        .abi_include = null,
        .slibdir = "/lib64",
        .min_kernel = .{ 3, 2, 0 },
        .is_64bit = true,
        .config_defines = &.{
            .{ .name = "DEFAULT_DL_X86_CET_CONTROL", .value = "cet_elf_property" },
            .{ .name = "INCLUDE_X86_ISA_LEVEL", .value = "1" },
            .{ .name = "MINIMUM_X86_ISA_LEVEL", .value = "1" },
            .{ .name = "HAVE_X86_LAHF_SAHF", .value = "1" },
            .{ .name = "HAVE_X86_INLINE_TRUNC", .value = "1" },
            .{ .name = "HAVE_X86_LIBGCC_CMP_RETURN_ATTR", .value = "1" },
            .{ .name = "HAVE_X86_INLINE_FMOD", .value = "1" },
            .{ .name = "SUPPORT_STATIC_PIE", .value = "1" },
            .{ .name = "ENABLE_STATIC_PIE", .value = "1" },
        },
    },
    .{
        .name = "x32",
        .base_machine = "x86_64",
        .machine = "x86_64/x32",
        .config_triple = "x86_64-pc-linux-gnux32",
        .zig_target = "x86_64-linux-gnux32",
        .default_abi = "x32",
        .abi_variants = &x86_abi_variants,
        .abi_include = null,
        .slibdir = "/libx32",
        .min_kernel = .{ 3, 4, 0 },
        .is_64bit = false,
        .config_defines = &.{
            .{ .name = "DEFAULT_DL_X86_CET_CONTROL", .value = "cet_elf_property" },
            .{ .name = "INCLUDE_X86_ISA_LEVEL", .value = "1" },
            .{ .name = "MINIMUM_X86_ISA_LEVEL", .value = "1" },
            .{ .name = "HAVE_X86_LAHF_SAHF", .value = "1" },
            .{ .name = "HAVE_X86_INLINE_TRUNC", .value = "1" },
            .{ .name = "HAVE_X86_LIBGCC_CMP_RETURN_ATTR", .value = "1" },
            .{ .name = "HAVE_X86_INLINE_FMOD", .value = "1" },
            .{ .name = "SUPPORT_STATIC_PIE", .value = "1" },
            .{ .name = "ENABLE_STATIC_PIE", .value = "1" },
        },
    },
    .{
        .name = "i686",
        .base_machine = "i386",
        .machine = "i386/i686",
        .config_triple = "i686-pc-linux-gnu",
        .zig_target = "x86-linux-gnu",
        .default_abi = "32",
        .abi_variants = &x86_abi_variants,
        .abi_include = null,
        .slibdir = "/lib",
        .min_kernel = .{ 3, 2, 0 },
        .is_64bit = false,
        .config_defines = &.{
            .{ .name = "INCLUDE_X86_ISA_LEVEL", .value = "1" },
            .{ .name = "MINIMUM_X86_ISA_LEVEL", .value = "1" },
            .{ .name = "HAVE_X86_INLINE_TRUNC", .value = "1" },
            .{ .name = "HAVE_X86_LIBGCC_CMP_RETURN_ATTR", .value = "1" },
            .{ .name = "HAVE_X86_INLINE_FMOD", .value = "1" },
            .{ .name = "SUPPORT_STATIC_PIE", .value = "1" },
            .{ .name = "ENABLE_STATIC_PIE", .value = "1" },
            .{ .name = "EXPORT_UNWIND_FIND_FDE", .value = "1" },
        },
    },
    .{
        .name = "aarch64",
        .base_machine = "aarch64",
        .machine = "aarch64",
        .config_triple = "aarch64-unknown-linux-gnu",
        .zig_target = "aarch64-linux-gnu",
        .default_abi = "lp64",
        .abi_variants = &aarch64_abi_variants,
        .slibdir = "/lib64",
        .min_kernel = .{ 3, 7, 0 },
        .is_64bit = true,
        .config_defines = &.{
            .{ .name = "SUPPORT_STATIC_PIE", .value = "1" },
            .{ .name = "ENABLE_STATIC_PIE", .value = "1" },
            .{ .name = "HAVE_AARCH64_SVE_ASM", .value = "1" },
            .{ .name = "HAVE_AARCH64_PAC_RET", .value = "1" },
            .{ .name = "HAVE_AARCH64_BTI", .value = "1" },
        },
    },
    .{
        .name = "aarch64_be",
        .base_machine = "aarch64",
        .machine = "aarch64",
        .config_triple = "aarch64_be-unknown-linux-gnu",
        .zig_target = "aarch64_be-linux-gnu",
        .default_abi = "lp64_be",
        .abi_variants = &aarch64_abi_variants,
        .slibdir = "/lib64",
        .min_kernel = .{ 3, 7, 0 },
        .is_64bit = true,
        .config_defines = &.{
            .{ .name = "HAVE_AARCH64_BE", .value = "1" },
            .{ .name = "SUPPORT_STATIC_PIE", .value = "1" },
            .{ .name = "ENABLE_STATIC_PIE", .value = "1" },
            .{ .name = "HAVE_AARCH64_SVE_ASM", .value = "1" },
            .{ .name = "HAVE_AARCH64_PAC_RET", .value = "1" },
            .{ .name = "HAVE_AARCH64_BTI", .value = "1" },
        },
    },
    .{
        .name = "arm",
        .base_machine = "arm",
        .machine = "arm/le/armv7",
        .config_triple = "arm-unknown-linux-gnueabihf",
        .zig_target = "arm-linux-gnueabihf",
        .default_abi = "hard",
        .abi_variants = &arm_abi_variants,
        .abi_include = null,
        .slibdir = "/lib",
        .min_kernel = .{ 3, 2, 0 },
        .is_64bit = false,
        .config_defines = &.{
            .{ .name = "HAVE_ARM_PCS_VFP", .value = "1" },
            .{ .name = "ARM_PCREL_MOVW_OK", .value = "1" },
            .{ .name = "SUPPORT_STATIC_PIE", .value = "1" },
            .{ .name = "ENABLE_STATIC_PIE", .value = "1" },
        },
    },
    .{
        .name = "arm_soft",
        .base_machine = "arm",
        .machine = "arm/le/armv7",
        .config_triple = "arm-unknown-linux-gnueabi",
        .zig_target = "arm-linux-gnueabi",
        .with_fp = false,
        .default_abi = "soft",
        .abi_variants = &arm_abi_variants,
        .abi_include = null,
        .slibdir = "/lib",
        .min_kernel = .{ 3, 2, 0 },
        .is_64bit = false,
        .config_defines = &.{
            .{ .name = "ARM_PCREL_MOVW_OK", .value = "1" },
            .{ .name = "SUPPORT_STATIC_PIE", .value = "1" },
            .{ .name = "ENABLE_STATIC_PIE", .value = "1" },
        },
    },
    .{
        .name = "riscv64",
        .base_machine = "riscv",
        .machine = "riscv/rv64/rvd",
        .config_triple = "riscv64-unknown-linux-gnu",
        .zig_target = "riscv64-linux-gnu",
        .default_abi = "lp64d",
        .abi_variants = &riscv_abi_variants,
        .slibdir = "/lib64/lp64d",
        .min_kernel = .{ 4, 15, 0 },
        .is_64bit = true,
        .config_defines = &.{
            .{ .name = "RISCV_ABI_XLEN", .value = "64" },
            .{ .name = "RISCV_ABI_FLEN", .value = "64" },
            .{ .name = "SUPPORT_STATIC_PIE", .value = "1" },
            .{ .name = "ENABLE_STATIC_PIE", .value = "1" },
        },
    },
    .{
        .name = "riscv32",
        .base_machine = "riscv",
        .machine = "riscv/rv32/rvd",
        .config_triple = "riscv32-unknown-linux-gnu",
        .zig_target = "riscv32-linux-gnu",
        .default_abi = "ilp32d",
        .abi_variants = &riscv_abi_variants,
        .slibdir = "/lib32/ilp32d",
        .min_kernel = .{ 5, 4, 0 },
        .is_64bit = false,
        .config_defines = &.{
            .{ .name = "RISCV_ABI_XLEN", .value = "32" },
            .{ .name = "RISCV_ABI_FLEN", .value = "64" },
            .{ .name = "SUPPORT_STATIC_PIE", .value = "1" },
            .{ .name = "ENABLE_STATIC_PIE", .value = "1" },
        },
    },
    .{
        .name = "powerpc64le",
        .base_machine = "powerpc",
        .machine = "powerpc/powerpc64/le",
        .config_triple = "powerpc64le-unknown-linux-gnu",
        .zig_target = "powerpc64le-linux-gnu",
        .default_abi = "64-v2",
        .abi_variants = &powerpc_abi_variants,
        .slibdir = "/lib64",
        .min_kernel = .{ 3, 10, 0 },
        .is_64bit = true,
        .config_defines = &.{
            .{ .name = "HIDDEN_VAR_NEEDS_DYNAMIC_RELOC", .value = "1" },
            .{ .name = "HAVE_ELFV2_ABI", .value = "1" },
            .{ .name = "USE_PPC64_NOTOC", .value = "1" },
            .{ .name = "USE_PPC_SCV", .value = "1" },
        },
    },
    .{
        .name = "s390x",
        .base_machine = "s390",
        .machine = "s390",
        .config_triple = "s390x-ibm-linux-gnu",
        .zig_target = "s390x-linux-gnu",
        .default_abi = "default",
        .abi_variants = &.{},
        .slibdir = "/lib64",
        .min_kernel = .{ 3, 2, 0 },
        .is_64bit = true,
        .config_defines = &.{
            .{ .name = "HAVE_S390_VX_ASM_SUPPORT", .value = "1" },
            .{ .name = "HAVE_S390_VX_GCC_SUPPORT", .value = "1" },
            .{ .name = "HAVE_S390_ARCH13_ASM_SUPPORT", .value = "1" },
            .{ .name = "SUPPORT_STATIC_PIE", .value = "1" },
            .{ .name = "ENABLE_STATIC_PIE", .value = "1" },
            .{ .name = "EXPORT_UNWIND_FIND_FDE", .value = "1" },
        },
    },
    .{
        .name = "loongarch64",
        .base_machine = "loongarch",
        .machine = "loongarch/lp64",
        .config_triple = "loongarch64-unknown-linux-gnu",
        .zig_target = "loongarch64-linux-gnu",
        .default_abi = "lp64d",
        .abi_variants = &loongarch_abi_variants,
        .slibdir = "/lib64",
        .min_kernel = .{ 5, 19, 0 },
        .is_64bit = true,
        .config_defines = &.{
            .{ .name = "LOONGARCH_ABI_GRLEN", .value = "64" },
            .{ .name = "LOONGARCH_ABI_FRLEN", .value = "64" },
            .{ .name = "HIDDEN_VAR_NEEDS_DYNAMIC_RELOC", .value = "1" },
            .{ .name = "SUPPORT_STATIC_PIE", .value = "1" },
            .{ .name = "ENABLE_STATIC_PIE", .value = "1" },
            .{ .name = "HAVE_LOONGARCH_VEC_COM", .value = "1" },
        },
    },
    .{
        .name = "mips64el",
        .base_machine = "mips",
        .machine = "mips/mips64/n64",
        .config_triple = "mips64el-unknown-linux-gnuabi64",
        .zig_target = "mips64el-linux-gnuabi64",
        .default_abi = "n64_hard",
        .abi_variants = &mips_abi_variants,
        .abi_include = "sgidefs.h",
        .slibdir = "/lib64",
        .min_kernel = .{ 3, 2, 0 },
        .is_64bit = true,
        .config_defines = &.{
            .{ .name = "HIDDEN_VAR_NEEDS_DYNAMIC_RELOC", .value = "1" },
            .{ .name = "EXPORT_UNWIND_FIND_FDE", .value = "1" },
        },
    },
    .{
        .name = "mips64",
        .base_machine = "mips",
        .machine = "mips/mips64/n64",
        .config_triple = "mips64-unknown-linux-gnuabi64",
        .zig_target = "mips64-linux-gnuabi64",
        .default_abi = "n64_hard",
        .abi_variants = &mips_abi_variants,
        .abi_include = "sgidefs.h",
        .slibdir = "/lib64",
        .min_kernel = .{ 3, 2, 0 },
        .is_64bit = true,
        .config_defines = &.{
            .{ .name = "HIDDEN_VAR_NEEDS_DYNAMIC_RELOC", .value = "1" },
            .{ .name = "EXPORT_UNWIND_FIND_FDE", .value = "1" },
        },
    },
    .{
        .name = "mips64el_n32",
        .base_machine = "mips",
        .machine = "mips/mips64/n32",
        .config_triple = "mips64el-unknown-linux-gnuabin32",
        .zig_target = "mips64el-linux-gnuabin32",
        .default_abi = "n32_hard",
        .abi_variants = &mips_abi_variants,
        .abi_include = "sgidefs.h",
        .slibdir = "/lib32",
        .min_kernel = .{ 3, 2, 0 },
        .is_64bit = false,
        .config_defines = &.{
            .{ .name = "HIDDEN_VAR_NEEDS_DYNAMIC_RELOC", .value = "1" },
            .{ .name = "EXPORT_UNWIND_FIND_FDE", .value = "1" },
        },
    },
    .{
        .name = "mips64_n32",
        .base_machine = "mips",
        .machine = "mips/mips64/n32",
        .config_triple = "mips64-unknown-linux-gnuabin32",
        .zig_target = "mips64-linux-gnuabin32",
        .default_abi = "n32_hard",
        .abi_variants = &mips_abi_variants,
        .abi_include = "sgidefs.h",
        .slibdir = "/lib32",
        .min_kernel = .{ 3, 2, 0 },
        .is_64bit = false,
        .config_defines = &.{
            .{ .name = "HIDDEN_VAR_NEEDS_DYNAMIC_RELOC", .value = "1" },
            .{ .name = "EXPORT_UNWIND_FIND_FDE", .value = "1" },
        },
    },
    .{
        .name = "mipsel",
        .base_machine = "mips",
        .machine = "mips/mips32",
        .config_triple = "mipsel-unknown-linux-gnu",
        .zig_target = "mipsel-linux-gnueabihf",
        .default_abi = "o32_hard",
        .abi_variants = &mips_abi_variants,
        .abi_include = "sgidefs.h",
        .slibdir = "/lib",
        .min_kernel = .{ 3, 2, 0 },
        .is_64bit = false,
        .config_defines = &.{
            .{ .name = "HIDDEN_VAR_NEEDS_DYNAMIC_RELOC", .value = "1" },
            .{ .name = "EXPORT_UNWIND_FIND_FDE", .value = "1" },
        },
    },
    .{
        .name = "mips",
        .base_machine = "mips",
        .machine = "mips/mips32",
        .config_triple = "mips-unknown-linux-gnu",
        .zig_target = "mips-linux-gnueabihf",
        .default_abi = "o32_hard",
        .abi_variants = &mips_abi_variants,
        .abi_include = "sgidefs.h",
        .slibdir = "/lib",
        .min_kernel = .{ 3, 2, 0 },
        .is_64bit = false,
        .config_defines = &.{
            .{ .name = "HIDDEN_VAR_NEEDS_DYNAMIC_RELOC", .value = "1" },
            .{ .name = "EXPORT_UNWIND_FIND_FDE", .value = "1" },
        },
    },
    .{
        .name = "sparc64",
        .base_machine = "sparc",
        .machine = "sparc/sparc64",
        .config_triple = "sparc64-unknown-linux-gnu",
        .zig_target = "sparc64-linux-gnu",
        .default_abi = "64",
        .abi_variants = &sparc_abi_variants,
        .slibdir = "/lib64",
        .min_kernel = .{ 3, 2, 0 },
        .is_64bit = true,
        .config_defines = &.{
            .{ .name = "EXPORT_UNWIND_FIND_FDE", .value = "1" },
        },
    },
    .{
        .name = "sparc",
        .base_machine = "sparc",
        .machine = "sparc/sparc32/sparcv9",
        .config_triple = "sparcv9-unknown-linux-gnu",
        .zig_target = "sparc-linux-gnu",
        .default_abi = "32",
        .abi_variants = &sparc_abi_variants,
        .slibdir = "/lib",
        .min_kernel = .{ 3, 2, 0 },
        .is_64bit = false,
        .config_defines = &.{
            .{ .name = "EXPORT_UNWIND_FIND_FDE", .value = "1" },
        },
    },
};

pub fn findArch(name: []const u8) ?ArchConfig {
    for (supported_archs) |arch| {
        if (std.mem.eql(u8, arch.name, name)) return arch;
    }
    return null;
}

fn dirExists(io: Io, sub_path: []const u8) bool {
    var dir = Io.Dir.cwd().openDir(io, sub_path, .{}) catch return false;
    dir.close(io);
    return true;
}

fn readImpliesFile(gpa: Allocator, io: Io, dir_path: []const u8, file_name: []const u8, out_list: *std.ArrayList([]const u8)) !void {
    const full_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ dir_path, file_name });
    defer gpa.free(full_path);

    const content = Io.Dir.cwd().readFileAlloc(io, full_path, gpa, .unlimited) catch return;
    defer gpa.free(content);

    var line_it = std.mem.splitScalar(u8, content, '\n');
    while (line_it.next()) |raw_line| {
        const no_comment = if (std.mem.indexOfScalar(u8, raw_line, '#')) |idx| raw_line[0..idx] else raw_line;
        const trimmed = std.mem.trim(u8, no_comment, " \t\r");
        if (trimmed.len == 0) continue;

        const cand = try std.fmt.allocPrint(gpa, "sysdeps/{s}", .{trimmed});
        if (dirExists(io, cand)) {
            try out_list.append(gpa, cand);
        } else {
            gpa.free(cand);
        }
    }
}

/// Resolves the ordered list of sysdeps directories for `arch` using the exact
/// algorithm from glibc's `configure.ac` (lines 912-1080).
pub fn resolveSysdirs(gpa: Allocator, io: Io, arch: ArchConfig) ![][]const u8 {
    var mach: std.ArrayList([]const u8) = .empty;
    defer {
        for (mach.items) |m| gpa.free(m);
        mach.deinit(gpa);
    }

    const fpu_sub = if (arch.with_fp) "/fpu" else "/nofpu";
    var cur_mach: []const u8 = arch.machine;
    while (true) {
        try mach.append(gpa, try std.fmt.allocPrint(gpa, "/{s}{s}/multiarch", .{ cur_mach, fpu_sub }));
        try mach.append(gpa, try std.fmt.allocPrint(gpa, "/{s}{s}", .{ cur_mach, fpu_sub }));
        try mach.append(gpa, try std.fmt.allocPrint(gpa, "/{s}/multiarch", .{cur_mach}));
        try mach.append(gpa, try std.fmt.allocPrint(gpa, "/{s}", .{cur_mach}));
        if (std.mem.lastIndexOfScalar(u8, cur_mach, '/')) |idx| {
            cur_mach = cur_mach[0..idx];
        } else {
            break;
        }
    }
    try mach.append(gpa, try gpa.dupe(u8, ""));

    const bases = [_][]const u8{ "/unix/sysv", "/unix", "" };
    const ostries = [_][]const u8{ "/linux", "" };

    var worklist: std.ArrayList([]const u8) = .empty;
    defer {
        for (worklist.items) |w| gpa.free(w);
        worklist.deinit(gpa);
    }

    for (bases) |b| {
        for (mach.items) |m0| {
            for (ostries) |o| {
                if (b.len == 0 and o.len != 0) continue;
                for (mach.items) |m| {
                    const try_path = try std.fmt.allocPrint(gpa, "sysdeps{s}{s}{s}{s}", .{ m0, b, o, m });
                    if (std.mem.eql(u8, try_path, "sysdeps")) {
                        gpa.free(try_path);
                        continue;
                    }
                    if (dirExists(io, try_path)) {
                        try worklist.append(gpa, try_path);
                    } else {
                        gpa.free(try_path);
                    }
                }
            }
        }
    }

    var names: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (names.items) |n| gpa.free(n);
        names.deinit(gpa);
    }

    while (worklist.items.len > 0) {
        const name = worklist.orderedRemove(0);
        var already_in = false;
        for (names.items) |existing| {
            if (std.mem.eql(u8, existing, name)) {
                already_in = true;
                break;
            }
        }
        if (already_in) {
            gpa.free(name);
            continue;
        }

        var implies: std.ArrayList([]const u8) = .empty;
        defer implies.deinit(gpa);
        var implies_before: std.ArrayList([]const u8) = .empty;
        defer implies_before.deinit(gpa);
        var implies_after: std.ArrayList([]const u8) = .empty;
        defer implies_after.deinit(gpa);

        try readImpliesFile(gpa, io, name, "Implies", &implies);
        try readImpliesFile(gpa, io, name, "Implies-before", &implies_before);
        try readImpliesFile(gpa, io, name, "Implies-after", &implies_after);

        try names.append(gpa, name);

        var parent_opt: ?[]const u8 = null;
        if (std.mem.lastIndexOfScalar(u8, name, '/')) |slash_idx| {
            const parent_slice = name[0..slash_idx];
            if (!std.mem.eql(u8, parent_slice, "sysdeps")) {
                parent_opt = try gpa.dupe(u8, parent_slice);
            }
        }

        // New worklist order per configure.ac:
        // implies ++ rest_of_worklist ++ implies_before ++ parent ++ implies_after
        var new_worklist: std.ArrayList([]const u8) = .empty;
        try new_worklist.appendSlice(gpa, implies.items);
        try new_worklist.appendSlice(gpa, worklist.items);
        try new_worklist.appendSlice(gpa, implies_before.items);
        if (parent_opt) |p| {
            try new_worklist.append(gpa, p);
        }
        try new_worklist.appendSlice(gpa, implies_after.items);

        worklist.deinit(gpa);
        worklist = new_worklist;
    }

    try names.append(gpa, try gpa.dupe(u8, "sysdeps/generic"));
    return names.toOwnedSlice(gpa);
}
