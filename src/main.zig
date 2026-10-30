const std = @import("std");
const Io = std.Io;
const archs = @import("archs.zig");
const math_data = @import("math_data.zig");

const all_subdirs = [_][]const u8{
    "csu",          "assert", "ctype",      "locale",   "intl",
    "catgets",      "math",   "setjmp",     "signal",   "stdlib",
    "stdio-common", "libio",  "malloc",     "string",   "wcsmbs",
    "time",         "dirent", "posix",      "io",       "termios",
    "resource",     "misc",   "socket",     "sysvipc",  "gmon",
    "gnulib",       "iconv",  "iconvdata",  "wctype",   "manual",
    "po",           "argp",   "localedata", "timezone", "rt",
    "conform",      "debug",  "mathvec",    "support",  "dlfcn",
    "elf",          "nptl",   "nptl_db",    "nss",      "hesiod",
    "sunrpc",       "inet",   "login",
};

const common_sym_files = [_][]const u8{
    "csu/rtld-sizes.sym",
    "csu/sem_t-align.sym",
    "libio/libio-macros.sym",
    "nptl/descr-const.sym",
    "nptl/unwindbuf.sym",
    "setjmp/jmp_buf-macros.sym",
};

const nss_databases = [_][]const u8{
    "ethers",
    "grp",
    "netgrp",
    "proto",
    "pwd",
    "service",
    "sgrp",
    "spwd",
    "rpc",
    "initgroups",
};

pub const GenStats = struct {
    headers: usize = 0,
    c_sources: usize = 0,
    asm_sources: usize = 0,
    map_files: usize = 0,
};

fn fileExists(io: Io, path: []const u8) bool {
    Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

fn buildIncludeFlags(
    gpa: std.mem.Allocator,
    io: Io,
    arch_out_dir: []const u8,
    sysdirs: []const []const u8,
) !std.ArrayList([]const u8) {
    var flags: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (flags.items) |f| gpa.free(f);
        flags.deinit(gpa);
    }

    try flags.append(gpa, try gpa.dupe(u8, "-Iinclude"));
    try flags.append(gpa, try std.fmt.allocPrint(gpa, "-I{s}", .{arch_out_dir}));

    for (sysdirs) |sdir| {
        const inc_sub = try std.fmt.allocPrint(gpa, "{s}/include", .{sdir});
        defer gpa.free(inc_sub);
        if (fileExists(io, inc_sub)) {
            try flags.append(gpa, try std.fmt.allocPrint(gpa, "-I{s}/include", .{sdir}));
        }
        try flags.append(gpa, try std.fmt.allocPrint(gpa, "-I{s}", .{sdir}));
    }

    try flags.append(gpa, try gpa.dupe(u8, "-Ilibio"));
    try flags.append(gpa, try gpa.dupe(u8, "-Inptl"));
    try flags.append(gpa, try gpa.dupe(u8, "-I."));
    return flags;
}

fn runCmd(gpa: std.mem.Allocator, io: Io, argv: []const []const u8) ![]u8 {
    const res = try std.process.run(gpa, io, .{
        .argv = argv,
    });
    defer gpa.free(res.stderr);
    switch (res.term) {
        .exited => |code| if (code != 0) {
            std.debug.print("Command failed (exit {d}):\n", .{code});
            for (argv) |a| std.debug.print("{s} ", .{a});
            std.debug.print("\nstderr:\n{s}\n", .{res.stderr});
            gpa.free(res.stdout);
            return error.CommandFailed;
        },
        else => {
            std.debug.print("Command terminated abnormally:\nstderr:\n{s}\n", .{res.stderr});
            gpa.free(res.stdout);
            return error.CommandFailed;
        },
    }
    return res.stdout;
}

const KernelVer = struct {
    major: u32,
    minor: u32,
    sub: u32,
    code: u32,
};

fn parseKernelVersion(ver: [3]u32) KernelVer {
    return .{
        .major = ver[0],
        .minor = ver[1],
        .sub = ver[2],
        .code = (ver[0] * 65536) + (ver[1] * 256) + ver[2],
    };
}

/// Replace leading `%` preprocessor directives (`%if`, `%ifdef`, `%ifndef`, `%elif`, `%else`, `%endif`)
/// with `#` so `zig cc -E` can preprocess `shlib-versions` and `Versions` files.
fn appendPercentPreprocessed(gpa: std.mem.Allocator, out: *std.ArrayList(u8), content: []const u8) !void {
    var line_it = std.mem.splitScalar(u8, content, '\n');
    while (line_it.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        const trimmed_start = std.mem.trimStart(u8, line, " \t");
        if (std.mem.startsWith(u8, trimmed_start, "%")) {
            try out.append(gpa, '#');
            try out.appendSlice(gpa, trimmed_start[1..]);
            try out.append(gpa, '\n');
        } else {
            try out.appendSlice(gpa, line);
            try out.append(gpa, '\n');
        }
    }
}

/// Strip `#` comment lines and empty lines from preprocessor output.
fn stripPreprocessedOutput(gpa: std.mem.Allocator, raw: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var line_it = std.mem.splitScalar(u8, raw, '\n');
    while (line_it.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0) continue;
        if (trimmed[0] == '#') continue;
        // Strip inline comments starting with `#`
        const final_line = if (std.mem.indexOfScalar(u8, line, '#')) |idx|
            std.mem.trimEnd(u8, line[0..idx], " \t")
        else
            line;
        if (final_line.len == 0) continue;
        try out.appendSlice(gpa, final_line);
        try out.append(gpa, '\n');
    }
    return out.toOwnedSlice(gpa);
}

fn generateConfigH(
    gpa: std.mem.Allocator,
    io: Io,
    arch: archs.ArchConfig,
    arch_out_dir: []const u8,
) !void {
    const template = try Io.Dir.cwd().readFileAlloc(io, "config.h.in", gpa, .unlimited);
    defer gpa.free(template);

    const kver = parseKernelVersion(arch.min_kernel);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);

    try out.appendSlice(gpa, "#ifndef _GLIBC_ZIG_CONFIG_H\n#define _GLIBC_ZIG_CONFIG_H 1\n");
    try out.appendSlice(gpa, template);
    try out.appendSlice(gpa, "\n/* Generated by Zig glibc generator for target ");
    try out.appendSlice(gpa, arch.name);
    try out.appendSlice(gpa, " */\n");

    const CommonDef = struct { key: []const u8, val: []const u8 };
    const kver_str = try std.fmt.allocPrint(gpa, "{d}", .{kver.code});
    defer gpa.free(kver_str);
    const kver_quoted = try std.fmt.allocPrint(gpa, "\"{d}.{d}.{d}\"", .{ kver.major, kver.minor, kver.sub });
    defer gpa.free(kver_quoted);
    const abi_tag_ver = try std.fmt.allocPrint(gpa, "{d},{d},{d}", .{ kver.major, kver.minor, kver.sub });
    defer gpa.free(abi_tag_ver);

    const common_defs = [_]CommonDef{
        .{ .key = "__LINUX_KERNEL_VERSION", .val = kver_str },
        .{ .key = "__LINUX_KERNEL_VERSION_STR", .val = kver_quoted },
        .{ .key = "__ABI_TAG_VERSION", .val = abi_tag_ver },
        .{ .key = "USE_MULTIARCH", .val = "1" },
        .{ .key = "HAVE_IFUNC", .val = "1" },
        .{ .key = "HAVE_GCC_IFUNC", .val = "1" },
        .{ .key = "HAVE_INLINED_SYSCALLS", .val = "1" },
        .{ .key = "__PTHREAD_NPTL", .val = "1" },
        .{ .key = "SYSCALL_CANCEL", .val = "1" },
        .{ .key = "HAVE_TUNABLES", .val = "1" },
        .{ .key = "TOP_NAMESPACE", .val = "glibc" },
        .{ .key = "USE_NSCD", .val = "1" },
        .{ .key = "SUPPORT_STATIC_PIE", .val = if (arch.is_64bit) "1" else "0" },
        .{ .key = "ENABLE_STATIC_PIE", .val = "0" },
        .{ .key = "USE_LDCONFIG", .val = "1" },
        .{ .key = "HAVE_Z_COMBRELOC", .val = "1" },
        .{ .key = "HAVE_GLOB_DAT_RELOC", .val = "1" },
        .{ .key = "HAVE_GNU_RETAIN", .val = "1" },
        .{ .key = "HAVE_SDATA_SECTION", .val = "0" },
        .{ .key = "HAVE_CC_INHIBIT_LOOP_TO_LIBCALL", .val = "1" },
        .{ .key = "STACK_PROTECTOR_LEVEL", .val = "0" },
        .{ .key = "HAVE_CC_NO_STACK_PROTECTOR", .val = "1" },
        .{ .key = "HAVE_ASM_SET_DIRECTIVE", .val = "1" },
        .{ .key = "HAVE_BUILTIN_MEMSET", .val = "1" },
        .{ .key = "HAVE_BUILTIN_TRAP", .val = "1" },
        .{ .key = "HAVE_64B_ATOMICS", .val = if (arch.is_64bit) "1" else "0" },
        .{ .key = "ATTR_AFTER_FUNC_DECL", .val = "1" },
        .{ .key = "TIMEOUTFACTOR", .val = "1" },
        .{ .key = "PKGVERSION", .val = "\"(GNU libc) \"" },
        .{ .key = "REPORT_BUGS_TO", .val = "\"<https://www.gnu.org/software/libc/bugs.html>\"" },
    };

    for (common_defs) |d| {
        try out.print(gpa, "#undef {s}\n#define {s} {s}\n", .{ d.key, d.key, d.val });
    }
    for (arch.config_defines) |d| {
        try out.print(gpa, "#undef {s}\n#define {s} {s}\n", .{ d.name, d.name, d.value });
    }
    try out.appendSlice(gpa, "#endif /* _GLIBC_ZIG_CONFIG_H */\n");

    const config_h_path = try std.fmt.allocPrint(gpa, "{s}/config.h", .{arch_out_dir});
    defer gpa.free(config_h_path);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = config_h_path, .data = out.items });
}

fn generateShlibAndVersions(
    gpa: std.mem.Allocator,
    io: Io,
    arch: archs.ArchConfig,
    arch_out_dir: []const u8,
    sysdirs: []const []const u8,
    stats: *GenStats,
) !void {
    // 1. Collect shlib-versions files (sysdirs first, then subdirs, then top-level, per Makeconfig)
    var shlib_in: std.ArrayList(u8) = .empty;
    defer shlib_in.deinit(gpa);

    for (sysdirs) |sdir| {
        const p = try std.fmt.allocPrint(gpa, "{s}/shlib-versions", .{sdir});
        defer gpa.free(p);
        if (fileExists(io, p)) {
            const bytes = try Io.Dir.cwd().readFileAlloc(io, p, gpa, .unlimited);
            defer gpa.free(bytes);
            try appendPercentPreprocessed(gpa, &shlib_in, bytes);
        }
    }
    const base_shlib_files = [_][]const u8{
        "nptl/shlib-versions",
        "nptl_db/shlib-versions",
        "shlib-versions",
    };
    for (base_shlib_files) |f| {
        if (fileExists(io, f)) {
            const bytes = try Io.Dir.cwd().readFileAlloc(io, f, gpa, .unlimited);
            defer gpa.free(bytes);
            try appendPercentPreprocessed(gpa, &shlib_in, bytes);
        }
    }

    const shlib_in_path = try std.fmt.allocPrint(gpa, "{s}/shlib-versions.v.in", .{arch_out_dir});
    defer gpa.free(shlib_in_path);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = shlib_in_path, .data = shlib_in.items });

    const config_h_path = try std.fmt.allocPrint(gpa, "{s}/config.h", .{arch_out_dir});
    defer gpa.free(config_h_path);

    var include_flags = try buildIncludeFlags(gpa, io, arch_out_dir, sysdirs);
    defer {
        for (include_flags.items) |f| gpa.free(f);
        include_flags.deinit(gpa);
    }

    // Preprocess shlib-versions.v.in with zig cc
    {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(gpa);
        try argv.appendSlice(gpa, &.{
            "zig",
            "cc",
            "-target",
            arch.zig_target,
        });
        try argv.appendSlice(gpa, arch.extra_cflags);
        try argv.appendSlice(gpa, &.{
            "-E",
            "-P",
            "-undef",
            "-Wno-unused-command-line-argument",
            "-Wno-macro-redefined",
        });
        try argv.appendSlice(gpa, include_flags.items);
        try argv.appendSlice(gpa, &.{
            "-include",
            config_h_path,
            "-x",
            "assembler-with-cpp",
            shlib_in_path,
        });
        const raw_v = try runCmd(gpa, io, argv.items);
        defer gpa.free(raw_v);
        const clean_v = try stripPreprocessedOutput(gpa, raw_v);
        defer gpa.free(clean_v);

        const shlib_v_path = try std.fmt.allocPrint(gpa, "{s}/shlib-versions.v", .{arch_out_dir});
        defer gpa.free(shlib_v_path);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = shlib_v_path, .data = clean_v });
    }

    // 2. Run scripts/soversions.awk -> soversions.i
    const shlib_v_path = try std.fmt.allocPrint(gpa, "{s}/shlib-versions.v", .{arch_out_dir});
    defer gpa.free(shlib_v_path);
    const soversions_i_path = try std.fmt.allocPrint(gpa, "{s}/soversions.i", .{arch_out_dir});
    defer gpa.free(soversions_i_path);
    const all_sonames_path = try std.fmt.allocPrint(gpa, "{s}/all-sonames.in", .{arch_out_dir});
    defer gpa.free(all_sonames_path);
    {
        const cpu_arg = try std.fmt.allocPrint(gpa, "cpu={s}", .{arch.config_triple});
        defer gpa.free(cpu_arg);
        const soversions_out = try runCmd(gpa, io, &.{
            "gawk",
            "-v",
            "default_setname=",
            "-v",
            cpu_arg,
            "-v",
            "vendor=pc",
            "-v",
            "os=linux-gnu",
            "-f",
            "scripts/soversions.awk",
            shlib_v_path,
        });
        defer gpa.free(soversions_out);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = soversions_i_path, .data = soversions_out });

        // Extract ld.so soname for runtime-linker.h, build soversions.mk and all-sonames.in
        var ld_soname: []const u8 = "ld.so.1";
        var soversions_mk: std.ArrayList(u8) = .empty;
        defer soversions_mk.deinit(gpa);
        var all_sonames: std.ArrayList(u8) = .empty;
        defer all_sonames.deinit(gpa);

        var line_it = std.mem.splitScalar(u8, soversions_out, '\n');
        while (line_it.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            var tok_it = std.mem.tokenizeAny(u8, trimmed, " \t");
            const abi = tok_it.next() orelse continue;
            if (!std.mem.eql(u8, abi, "DEFAULT")) continue;
            const lib = tok_it.next() orelse continue;
            const ver_or_soname = tok_it.next() orelse continue;
            if (std.mem.eql(u8, lib, "ld")) {
                ld_soname = ver_or_soname;
            }
            if (ver_or_soname.len > 0 and std.ascii.isDigit(ver_or_soname[0])) {
                try soversions_mk.print(gpa, "{s}.so-version=.{s}\n", .{ lib, ver_or_soname });
                try all_sonames.print(gpa, "{s}={s}.so.{s}\n", .{ lib, lib, ver_or_soname });
            } else {
                try soversions_mk.print(gpa, "{s}.so-version={s}\n", .{ lib, ver_or_soname });
                try all_sonames.print(gpa, "{s}={s}\n", .{ lib, ver_or_soname });
            }
        }

        const soversions_mk_path = try std.fmt.allocPrint(gpa, "{s}/soversions.mk", .{arch_out_dir});
        defer gpa.free(soversions_mk_path);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = soversions_mk_path, .data = soversions_mk.items });
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = all_sonames_path, .data = all_sonames.items });

        const rt_linker_content = try std.fmt.allocPrint(
            gpa,
            "#define RUNTIME_LINKER \"{s}/{s}\"\n",
            .{ arch.slibdir, ld_soname },
        );
        defer gpa.free(rt_linker_content);
        const rt_linker_path = try std.fmt.allocPrint(gpa, "{s}/runtime-linker.h", .{arch_out_dir});
        defer gpa.free(rt_linker_path);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = rt_linker_path, .data = rt_linker_content });
        stats.headers += 1;
    }

    // 3. Generate libc-modules.h
    const libc_modules_path = try std.fmt.allocPrint(gpa, "{s}/libc-modules.h", .{arch_out_dir});
    defer gpa.free(libc_modules_path);
    {
        const modules_out = try runCmd(gpa, io, &.{
            "gawk",
            "-v",
            "buildlist=iconvprogs iconvdata ldconfig libmemusage libpcprofile librpcsvc locale_programs memusagestat nonlib nscd extramodules libnldbl libsupport testsuite testsuite_internal",
            "-f",
            "scripts/gen-libc-modules.awk",
            soversions_i_path,
        });
        defer gpa.free(modules_out);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = libc_modules_path, .data = modules_out });
        stats.headers += 1;
    }

    // 4. Generate gnu/lib-names.h, gnu/lib-names-<abi>.h, gnu/stubs.h, gnu/stubs-<abi>.h
    const gnu_dir = try std.fmt.allocPrint(gpa, "{s}/gnu", .{arch_out_dir});
    defer gpa.free(gnu_dir);
    try Io.Dir.cwd().createDirPath(io, gnu_dir);
    {
        const lib_names_sh = try std.fmt.allocPrint(
            gpa,
            "LC_ALL=C gawk -f scripts/lib-names.awk {s} | LC_ALL=C sort",
            .{all_sonames_path},
        );
        defer gpa.free(lib_names_sh);
        const lib_names_defines = try runCmd(gpa, io, &.{ "sh", "-c", lib_names_sh });
        defer gpa.free(lib_names_defines);

        const stubs_prologue_raw = try Io.Dir.cwd().readFileAlloc(io, "include/stubs-prologue.h", gpa, .unlimited);
        defer gpa.free(stubs_prologue_raw);
        var stubs_prologue_buf: std.ArrayList(u8) = .empty;
        defer stubs_prologue_buf.deinit(gpa);
        {
            var sp_it = std.mem.splitScalar(u8, stubs_prologue_raw, '\n');
            while (sp_it.next()) |line| {
                if (std.mem.startsWith(u8, line, "@")) continue;
                try stubs_prologue_buf.appendSlice(gpa, line);
                try stubs_prologue_buf.append(gpa, '\n');
            }
        }
        const stubs_prologue = stubs_prologue_buf.items;

        if (arch.abi_variants.len == 0) {
            var ln_buf: std.ArrayList(u8) = .empty;
            defer ln_buf.deinit(gpa);
            try ln_buf.appendSlice(gpa,
                \\/* This file is automatically generated.
                \\   It defines macros to allow user program to find the shared
                \\   library files which come as part of GNU libc.  */
                \\#ifndef __GNU_LIB_NAMES_H
                \\#define __GNU_LIB_NAMES_H 1
                \\
                \\
            );
            try ln_buf.appendSlice(gpa, lib_names_defines);
            try ln_buf.appendSlice(gpa, "\n#endif\t/* gnu/lib-names.h */\n");

            const ln_path = try std.fmt.allocPrint(gpa, "{s}/lib-names.h", .{gnu_dir});
            defer gpa.free(ln_path);
            try Io.Dir.cwd().writeFile(io, .{ .sub_path = ln_path, .data = ln_buf.items });
            stats.headers += 1;

            const st_path = try std.fmt.allocPrint(gpa, "{s}/stubs.h", .{gnu_dir});
            defer gpa.free(st_path);
            try Io.Dir.cwd().writeFile(io, .{ .sub_path = st_path, .data = stubs_prologue });
            stats.headers += 1;
        } else {
            var ln_abi_buf: std.ArrayList(u8) = .empty;
            defer ln_abi_buf.deinit(gpa);
            try ln_abi_buf.print(
                gpa,
                \\/* This file is automatically generated.  */
                \\#ifndef __GNU_LIB_NAMES_H
                \\# error "Never use <gnu/lib-names-{s}.h> directly; include <gnu/lib-names.h> instead."
                \\#endif
                \\
                \\
            ,
                .{arch.default_abi},
            );
            try ln_abi_buf.appendSlice(gpa, lib_names_defines);

            const ln_abi_path = try std.fmt.allocPrint(gpa, "{s}/lib-names-{s}.h", .{ gnu_dir, arch.default_abi });
            defer gpa.free(ln_abi_path);
            try Io.Dir.cwd().writeFile(io, .{ .sub_path = ln_abi_path, .data = ln_abi_buf.items });
            stats.headers += 1;

            const st_abi_path = try std.fmt.allocPrint(gpa, "{s}/stubs-{s}.h", .{ gnu_dir, arch.default_abi });
            defer gpa.free(st_abi_path);
            try Io.Dir.cwd().writeFile(io, .{ .sub_path = st_abi_path, .data = stubs_prologue });
            stats.headers += 1;

            var ln_wrapper: std.ArrayList(u8) = .empty;
            defer ln_wrapper.deinit(gpa);
            try ln_wrapper.appendSlice(gpa,
                \\/* This file is automatically generated.
                \\   It defines macros to allow user program to find the shared
                \\   library files which come as part of GNU libc.  */
                \\#ifndef __GNU_LIB_NAMES_H
                \\#define __GNU_LIB_NAMES_H 1
                \\
                \\
            );
            if (arch.abi_include) |inc| {
                try ln_wrapper.print(gpa, "#include <{s}>\n\n", .{inc});
            }
            for (arch.abi_variants) |v| {
                try ln_wrapper.print(
                    gpa,
                    "#if {s}\n# include <gnu/lib-names-{s}.h>\n#endif\n",
                    .{ v.condition, v.name },
                );
            }
            try ln_wrapper.appendSlice(gpa, "\n#endif\t/* gnu/lib-names.h */\n");

            const ln_path = try std.fmt.allocPrint(gpa, "{s}/lib-names.h", .{gnu_dir});
            defer gpa.free(ln_path);
            try Io.Dir.cwd().writeFile(io, .{ .sub_path = ln_path, .data = ln_wrapper.items });
            stats.headers += 1;

            var st_wrapper: std.ArrayList(u8) = .empty;
            defer st_wrapper.deinit(gpa);
            try st_wrapper.appendSlice(gpa,
                \\/* This file is automatically generated.
                \\   This file selects the right generated file of `__stub_FUNCTION' macros
                \\   based on the architecture being compiled for.  */
                \\
                \\
            );
            if (arch.abi_include) |inc| {
                try st_wrapper.print(gpa, "#include <{s}>\n\n", .{inc});
            }
            for (arch.abi_variants) |v| {
                try st_wrapper.print(
                    gpa,
                    "#if {s}\n# include <gnu/stubs-{s}.h>\n#endif\n",
                    .{ v.condition, v.name },
                );
            }
            const st_path = try std.fmt.allocPrint(gpa, "{s}/stubs.h", .{gnu_dir});
            defer gpa.free(st_path);
            try Io.Dir.cwd().writeFile(io, .{ .sub_path = st_path, .data = st_wrapper.items });
            stats.headers += 1;
        }
    }

    // 5. Collect Versions files across all_subdirs and sysdirs
    var versions_in: std.ArrayList(u8) = .empty;
    defer versions_in.deinit(gpa);

    for (all_subdirs) |sdir| {
        const p = try std.fmt.allocPrint(gpa, "{s}/Versions", .{sdir});
        defer gpa.free(p);
        if (fileExists(io, p)) {
            const bytes = try Io.Dir.cwd().readFileAlloc(io, p, gpa, .unlimited);
            defer gpa.free(bytes);
            try appendPercentPreprocessed(gpa, &versions_in, bytes);
        }
    }
    for (sysdirs) |sdir| {
        const p = try std.fmt.allocPrint(gpa, "{s}/Versions", .{sdir});
        defer gpa.free(p);
        if (fileExists(io, p)) {
            const bytes = try Io.Dir.cwd().readFileAlloc(io, p, gpa, .unlimited);
            defer gpa.free(bytes);
            try appendPercentPreprocessed(gpa, &versions_in, bytes);
        }
    }

    const versions_in_path = try std.fmt.allocPrint(gpa, "{s}/Versions.v.in", .{arch_out_dir});
    defer gpa.free(versions_in_path);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = versions_in_path, .data = versions_in.items });

    const versions_v_path = try std.fmt.allocPrint(gpa, "{s}/Versions.v", .{arch_out_dir});
    defer gpa.free(versions_v_path);
    {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(gpa);
        try argv.appendSlice(gpa, &.{
            "zig",
            "cc",
            "-target",
            arch.zig_target,
        });
        try argv.appendSlice(gpa, arch.extra_cflags);
        try argv.appendSlice(gpa, &.{
            "-E",
            "-P",
            "-undef",
            "-Wno-unused-command-line-argument",
            "-Wno-macro-redefined",
        });
        try argv.appendSlice(gpa, include_flags.items);
        try argv.appendSlice(gpa, &.{
            "-include",
            libc_modules_path,
            "-DMODULE_NAME=libc",
            "-include",
            "include/libc-symbols.h",
            "-x",
            "assembler-with-cpp",
            versions_in_path,
        });
        const raw_v = try runCmd(gpa, io, argv.items);
        defer gpa.free(raw_v);
        const clean_v = try stripPreprocessedOutput(gpa, raw_v);
        defer gpa.free(clean_v);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = versions_v_path, .data = clean_v });
    }

    // 6. Run scripts/versionlist.awk -> Versions.def
    const versions_def_path = try std.fmt.allocPrint(gpa, "{s}/Versions.def", .{arch_out_dir});
    defer gpa.free(versions_def_path);
    const versions_def_out = try runCmd(gpa, io, &.{
        "gawk",
        "-f",
        "scripts/versionlist.awk",
        versions_v_path,
    });
    defer gpa.free(versions_def_out);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = versions_def_path, .data = versions_def_out });

    // 7. Build Versions.def.combined and run scripts/firstversions.awk -> Versions.all
    const soversions_bytes = try Io.Dir.cwd().readFileAlloc(io, soversions_i_path, gpa, .unlimited);
    defer gpa.free(soversions_bytes);

    var combined_def: std.ArrayList(u8) = .empty;
    defer combined_def.deinit(gpa);
    {
        var line_it = std.mem.splitScalar(u8, soversions_bytes, '\n');
        while (line_it.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            var tok_it = std.mem.tokenizeAny(u8, trimmed, " \t");
            const abi = tok_it.next() orelse continue;
            if (!std.mem.eql(u8, abi, "DEFAULT")) continue;
            const lib = tok_it.next() orelse continue;
            _ = tok_it.next() orelse continue; // version/soname
            const rest = std.mem.trim(u8, tok_it.rest(), " \t");
            if (rest.len > 0) {
                try combined_def.print(gpa, "{s} : {s}\n", .{ lib, rest });
            }
        }
    }
    try combined_def.appendSlice(gpa, versions_def_out);

    const combined_def_path = try std.fmt.allocPrint(gpa, "{s}/Versions.def.combined", .{arch_out_dir});
    defer gpa.free(combined_def_path);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = combined_def_path, .data = combined_def.items });

    const versions_all_path = try std.fmt.allocPrint(gpa, "{s}/Versions.all", .{arch_out_dir});
    defer gpa.free(versions_all_path);
    const versions_all_out = try runCmd(gpa, io, &.{
        "gawk",
        "-f",
        "scripts/firstversions.awk",
        combined_def_path,
    });
    defer gpa.free(versions_all_out);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = versions_all_path, .data = versions_all_out });

    // 8. Run scripts/abi-versions.awk -> abi-versions.h, first-versions.h, ldbl-compat-choose.h
    const abi_versions_out = try runCmd(gpa, io, &.{
        "gawk",
        "-f",
        "scripts/abi-versions.awk",
        soversions_i_path,
        versions_all_path,
    });
    defer gpa.free(abi_versions_out);

    const abi_versions_h_path = try std.fmt.allocPrint(gpa, "{s}/abi-versions.h", .{arch_out_dir});
    defer gpa.free(abi_versions_h_path);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = abi_versions_h_path, .data = abi_versions_out });
    stats.headers += 1;

    {
        var fv: std.ArrayList(u8) = .empty;
        defer fv.deinit(gpa);
        var ldbl: std.ArrayList(u8) = .empty;
        defer ldbl.deinit(gpa);

        try fv.appendSlice(gpa, "#ifndef _FIRST_VERSIONS_H\n#define _FIRST_VERSIONS_H\n");
        try ldbl.appendSlice(gpa, "#ifndef _LDBL_COMPAT_CHOOSE_H\n#define _LDBL_COMPAT_CHOOSE_H\n");

        var line_it = std.mem.splitScalar(u8, abi_versions_out, '\n');
        while (line_it.next()) |line| {
            if (std.mem.indexOf(u8, line, "FIRST_VERSION_") != null) {
                try fv.appendSlice(gpa, line);
                try fv.append(gpa, '\n');
            }
            if (std.mem.indexOf(u8, line, "LDBL_COMPAT_") != null) {
                try ldbl.appendSlice(gpa, line);
                try ldbl.append(gpa, '\n');
            }
        }
        try fv.appendSlice(gpa, "#endif /* _FIRST_VERSIONS_H */\n");
        try ldbl.appendSlice(gpa, "#endif /* _LDBL_COMPAT_CHOOSE_H */\n");

        const fv_path = try std.fmt.allocPrint(gpa, "{s}/first-versions.h", .{arch_out_dir});
        defer gpa.free(fv_path);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = fv_path, .data = fv.items });
        stats.headers += 1;

        const ldbl_path = try std.fmt.allocPrint(gpa, "{s}/ldbl-compat-choose.h", .{arch_out_dir});
        defer gpa.free(ldbl_path);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = ldbl_path, .data = ldbl.items });
        stats.headers += 1;
    }

    // 9. Run scripts/haveversions.awk -> Versions.mk
    const versions_mk_out = try runCmd(gpa, io, &.{
        "gawk",
        "-f",
        "scripts/haveversions.awk",
        versions_all_path,
    });
    defer gpa.free(versions_mk_out);
    const versions_mk_path = try std.fmt.allocPrint(gpa, "{s}/Versions.mk", .{arch_out_dir});
    defer gpa.free(versions_mk_path);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = versions_mk_path, .data = versions_mk_out });

    // 10. Run scripts/versions.awk -> sysd-versions and all *.map files
    const buildroot_arg = try std.fmt.allocPrint(gpa, "buildroot={s}/", .{arch_out_dir});
    defer gpa.free(buildroot_arg);
    const defsfile_arg = try std.fmt.allocPrint(gpa, "defsfile={s}", .{versions_all_path});
    defer gpa.free(defsfile_arg);

    const sysd_versions_out = try runCmd(gpa, io, &.{
        "gawk",
        "-v",
        buildroot_arg,
        "-v",
        defsfile_arg,
        "-v",
        "move_if_change=mv -f",
        "-f",
        "scripts/versions.awk",
        versions_v_path,
    });
    defer gpa.free(sysd_versions_out);

    const sysd_versions_path = try std.fmt.allocPrint(gpa, "{s}/sysd-versions", .{arch_out_dir});
    defer gpa.free(sysd_versions_path);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = sysd_versions_path, .data = sysd_versions_out });

    // Count generated .map files from sysd_versions_out (`version-maps = ...`)
    var tok_it = std.mem.tokenizeAny(u8, sysd_versions_out, " \t\r\n");
    while (tok_it.next()) |tok| {
        if (std.mem.endsWith(u8, tok, ".map")) {
            stats.map_files += 1;
        }
    }
}

pub const CommonTargetIndepFiles = struct {
    posix_conf_vars_def_h: []const u8,
    c_translit_h: []const u8,
    msgs_h: []const u8,
    syscall_h: []const u8,
    plural_c: []const u8,
    nss_db_files: [nss_databases.len][]const u8,

    pub fn init(gpa: std.mem.Allocator, io: Io, base_out_dir: []const u8) !CommonTargetIndepFiles {
        try Io.Dir.cwd().createDirPath(io, base_out_dir);

        // 1. posix-conf-vars-def.h
        const posix_conf = try runCmd(gpa, io, &.{
            "gawk",
            "-f",
            "scripts/gen-posix-conf-vars.awk",
            "posix/posix-conf-vars.list",
        });

        // 2. locale/C-translit.h
        const c_translit = try runCmd(gpa, io, &.{
            "sh",
            "-c",
            "python3 -B locale/gen-translit.py < locale/C-translit.h.in",
        });

        // 3. intl/msgs.h
        const msgs_h = try runCmd(gpa, io, &.{
            "gawk",
            "-f",
            "intl/po2test.awk",
            "po/libc.pot",
        });

        // 4. bits/syscall.h
        const syscall_h = try runCmd(gpa, io, &.{
            "gawk",
            "-f",
            "sysdeps/unix/sysv/linux/gen-syscall-h.awk",
            "sysdeps/unix/sysv/linux/syscall-names.list",
        });

        // 5. intl/plural.c via bison
        const tmp_plural = try std.fmt.allocPrint(gpa, "{s}/.plural.c.tmp", .{base_out_dir});
        defer gpa.free(tmp_plural);
        const bison_out = try runCmd(gpa, io, &.{
            "bison",
            "-o",
            tmp_plural,
            "intl/plural.y",
        });
        gpa.free(bison_out);
        const plural_c = try Io.Dir.cwd().readFileAlloc(io, tmp_plural, gpa, .unlimited);

        // 6. nss/db-*.c
        var nss_files: [nss_databases.len][]const u8 = undefined;
        for (nss_databases, 0..) |db, i| {
            if (std.mem.eql(u8, db, "initgroups")) {
                nss_files[i] = try gpa.dupe(
                    u8,
                    "#include \"nss_files/files-initgroups.c\"\n",
                );
            } else {
                nss_files[i] = try std.fmt.allocPrint(
                    gpa,
                    "#define EXTERN_PARSER\n#define GENERIC \"nss_db/db-XXX.c\"\n#include \"nss_files/files-{s}.c\"\n",
                    .{db},
                );
            }
        }

        return .{
            .posix_conf_vars_def_h = posix_conf,
            .c_translit_h = c_translit,
            .msgs_h = msgs_h,
            .syscall_h = syscall_h,
            .plural_c = plural_c,
            .nss_db_files = nss_files,
        };
    }

    pub fn deinit(self: *const CommonTargetIndepFiles, gpa: std.mem.Allocator) void {
        gpa.free(self.posix_conf_vars_def_h);
        gpa.free(self.c_translit_h);
        gpa.free(self.msgs_h);
        gpa.free(self.syscall_h);
        gpa.free(self.plural_c);
        for (self.nss_db_files) |f| gpa.free(f);
    }
};

fn generateOtherHeadersAndSources(
    gpa: std.mem.Allocator,
    io: Io,
    arch: archs.ArchConfig,
    arch_out_dir: []const u8,
    sysdirs: []const []const u8,
    common: *const CommonTargetIndepFiles,
    stats: *GenStats,
) !void {
    // 1. dl-tunable-list.h
    {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(gpa);
        var extra_paths: std.ArrayList([]const u8) = .empty;
        defer {
            for (extra_paths.items) |p| gpa.free(p);
            extra_paths.deinit(gpa);
        }

        try argv.appendSlice(gpa, &.{
            "gawk",
            "-f",
            "scripts/gen-tunables.awk",
            "elf/dl-tunables.list",
        });
        for (sysdirs) |sdir| {
            const p = try std.fmt.allocPrint(gpa, "{s}/dl-tunables.list", .{sdir});
            if (fileExists(io, p)) {
                try extra_paths.append(gpa, p);
                try argv.append(gpa, p);
            } else {
                gpa.free(p);
            }
        }
        const tunables_out = try runCmd(gpa, io, argv.items);
        defer gpa.free(tunables_out);

        const p = try std.fmt.allocPrint(gpa, "{s}/dl-tunable-list.h", .{arch_out_dir});
        defer gpa.free(p);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = p, .data = tunables_out });
        stats.headers += 1;
    }

    // 2. libc-abis.h
    {
        var abis_file: []const u8 = "libc-abis";
        var owned_abis: ?[]u8 = null;
        defer if (owned_abis) |b| gpa.free(b);

        for (sysdirs) |sdir| {
            const candidate = try std.fmt.allocPrint(gpa, "{s}/libc-abis", .{sdir});
            if (fileExists(io, candidate)) {
                owned_abis = candidate;
                abis_file = candidate;
                break;
            }
            gpa.free(candidate);
        }

        const sh_cmd = try std.fmt.allocPrint(
            gpa,
            "sh scripts/gen-libc-abis {s}-linux-gnu < {s}",
            .{ arch.base_machine, abis_file },
        );
        defer gpa.free(sh_cmd);
        const abis_out = try runCmd(gpa, io, &.{ "sh", "-c", sh_cmd });
        defer gpa.free(abis_out);

        const p = try std.fmt.allocPrint(gpa, "{s}/libc-abis.h", .{arch_out_dir});
        defer gpa.free(p);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = p, .data = abis_out });
        stats.headers += 1;
    }

    // 3. gcc-macros.h
    {
        const dm_out = try runCmd(gpa, io, &.{
            "zig",
            "cc",
            "-target",
            arch.zig_target,
            "-E",
            "-dM",
            "-x",
            "c",
            "/dev/null",
        });
        defer gpa.free(dm_out);

        var macros_buf: std.ArrayList(u8) = .empty;
        defer macros_buf.deinit(gpa);
        var line_it = std.mem.splitScalar(u8, dm_out, '\n');
        while (line_it.next()) |line| {
            if (std.mem.startsWith(u8, line, "#define ")) {
                try macros_buf.appendSlice(gpa, "#define GCCMACRO");
                try macros_buf.appendSlice(gpa, line["#define ".len..]);
                try macros_buf.append(gpa, '\n');
            }
        }
        const p = try std.fmt.allocPrint(gpa, "{s}/gcc-macros.h", .{arch_out_dir});
        defer gpa.free(p);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = p, .data = macros_buf.items });
        stats.headers += 1;
    }

    // 4. csu/abi-tag.h
    const csu_dir = try std.fmt.allocPrint(gpa, "{s}/csu", .{arch_out_dir});
    defer gpa.free(csu_dir);
    try Io.Dir.cwd().createDirPath(io, csu_dir);
    {
        const kver = parseKernelVersion(arch.min_kernel);
        const abi_tag_content = try std.fmt.allocPrint(
            gpa,
            \\/* This file is automatically generated.  */
            \\#ifndef __ABI_TAG_OS
            \\# define __ABI_TAG_OS 0
            \\#endif
            \\#if !defined __ABI_TAG_VERSION && defined __LINUX_KERNEL_VERSION
            \\# define __ABI_TAG_VERSION {d},{d},{d}
            \\#endif
            \\
        ,
            .{ kver.major, kver.minor, kver.sub },
        );
        defer gpa.free(abi_tag_content);

        const p1 = try std.fmt.allocPrint(gpa, "{s}/abi-tag.h", .{csu_dir});
        defer gpa.free(p1);
        const p2 = try std.fmt.allocPrint(gpa, "{s}/abi-tag.h", .{arch_out_dir});
        defer gpa.free(p2);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = p1, .data = abi_tag_content });
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = p2, .data = abi_tag_content });
        stats.headers += 1;
    }

    // 5. elf/trusted-dirs.h
    const elf_dir = try std.fmt.allocPrint(gpa, "{s}/elf", .{arch_out_dir});
    defer gpa.free(elf_dir);
    try Io.Dir.cwd().createDirPath(io, elf_dir);
    {
        const sh_cmd = try std.fmt.allocPrint(
            gpa,
            "printf '/lib/\\n{s}/\\n' | gawk -f elf/gen-trusted-dirs.awk",
            .{arch.slibdir},
        );
        defer gpa.free(sh_cmd);
        const td_out = try runCmd(gpa, io, &.{ "sh", "-c", sh_cmd });
        defer gpa.free(td_out);

        const p1 = try std.fmt.allocPrint(gpa, "{s}/trusted-dirs.h", .{elf_dir});
        defer gpa.free(p1);
        const p2 = try std.fmt.allocPrint(gpa, "{s}/trusted-dirs.h", .{arch_out_dir});
        defer gpa.free(p2);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = p1, .data = td_out });
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = p2, .data = td_out });
        stats.headers += 1;
    }

    // 6. Write target-independent headers & C files into arch_out_dir
    {
        const posix_dir = try std.fmt.allocPrint(gpa, "{s}/posix", .{arch_out_dir});
        defer gpa.free(posix_dir);
        try Io.Dir.cwd().createDirPath(io, posix_dir);
        const p1 = try std.fmt.allocPrint(gpa, "{s}/posix-conf-vars-def.h", .{posix_dir});
        defer gpa.free(p1);
        const p2 = try std.fmt.allocPrint(gpa, "{s}/posix-conf-vars-def.h", .{arch_out_dir});
        defer gpa.free(p2);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = p1, .data = common.posix_conf_vars_def_h });
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = p2, .data = common.posix_conf_vars_def_h });
        stats.headers += 1;
    }
    {
        const locale_dir = try std.fmt.allocPrint(gpa, "{s}/locale", .{arch_out_dir});
        defer gpa.free(locale_dir);
        try Io.Dir.cwd().createDirPath(io, locale_dir);
        const p1 = try std.fmt.allocPrint(gpa, "{s}/C-translit.h", .{locale_dir});
        defer gpa.free(p1);
        const p2 = try std.fmt.allocPrint(gpa, "{s}/C-translit.h", .{arch_out_dir});
        defer gpa.free(p2);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = p1, .data = common.c_translit_h });
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = p2, .data = common.c_translit_h });
        stats.headers += 1;
    }
    {
        const intl_dir = try std.fmt.allocPrint(gpa, "{s}/intl", .{arch_out_dir});
        defer gpa.free(intl_dir);
        try Io.Dir.cwd().createDirPath(io, intl_dir);
        const p1 = try std.fmt.allocPrint(gpa, "{s}/msgs.h", .{intl_dir});
        defer gpa.free(p1);
        const p2 = try std.fmt.allocPrint(gpa, "{s}/msgs.h", .{arch_out_dir});
        defer gpa.free(p2);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = p1, .data = common.msgs_h });
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = p2, .data = common.msgs_h });
        stats.headers += 1;

        const plural_path = try std.fmt.allocPrint(gpa, "{s}/plural.c", .{intl_dir});
        defer gpa.free(plural_path);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = plural_path, .data = common.plural_c });
        stats.c_sources += 1;
    }
    {
        const bits_dir = try std.fmt.allocPrint(gpa, "{s}/bits", .{arch_out_dir});
        defer gpa.free(bits_dir);
        try Io.Dir.cwd().createDirPath(io, bits_dir);
        const misc_bits_dir = try std.fmt.allocPrint(gpa, "{s}/misc/bits", .{arch_out_dir});
        defer gpa.free(misc_bits_dir);
        try Io.Dir.cwd().createDirPath(io, misc_bits_dir);

        const p1 = try std.fmt.allocPrint(gpa, "{s}/syscall.h", .{bits_dir});
        defer gpa.free(p1);
        const p2 = try std.fmt.allocPrint(gpa, "{s}/syscall.h", .{misc_bits_dir});
        defer gpa.free(p2);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = p1, .data = common.syscall_h });
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = p2, .data = common.syscall_h });
        stats.headers += 1;
    }
    {
        const nss_dir = try std.fmt.allocPrint(gpa, "{s}/nss", .{arch_out_dir});
        defer gpa.free(nss_dir);
        try Io.Dir.cwd().createDirPath(io, nss_dir);
        for (nss_databases, 0..) |db, i| {
            const p = try std.fmt.allocPrint(gpa, "{s}/db-{s}.c", .{ nss_dir, db });
            defer gpa.free(p);
            try Io.Dir.cwd().writeFile(io, .{ .sub_path = p, .data = common.nss_db_files[i] });
            stats.c_sources += 1;
        }
    }
}

fn generateAsConstHeaders(
    gpa: std.mem.Allocator,
    io: Io,
    arch: archs.ArchConfig,
    arch_out_dir: []const u8,
    sysdirs: []const []const u8,
    stats: *GenStats,
) !void {
    // Collect unique .sym files in priority order (sysdirs first, then common_sym_files)
    const SymEntry = struct {
        stem: []const u8,
        path: []const u8,
    };
    var sym_entries: std.ArrayList(SymEntry) = .empty;
    defer {
        for (sym_entries.items) |e| {
            gpa.free(e.stem);
            gpa.free(e.path);
        }
        sym_entries.deinit(gpa);
    }

    const addSymIfNew = struct {
        fn call(
            alloc: std.mem.Allocator,
            list: *std.ArrayList(SymEntry),
            stem_raw: []const u8,
            full_path: []const u8,
        ) !void {
            for (list.items) |existing| {
                if (std.mem.eql(u8, existing.stem, stem_raw)) return;
            }
            try list.append(alloc, .{
                .stem = try alloc.dupe(u8, stem_raw),
                .path = try alloc.dupe(u8, full_path),
            });
        }
    }.call;

    // Parse gen-as-const-headers from <sysdir>/Makefile in sysdirs order
    for (sysdirs) |sdir| {
        const mk_path = try std.fmt.allocPrint(gpa, "{s}/Makefile", .{sdir});
        defer gpa.free(mk_path);
        if (!fileExists(io, mk_path)) continue;

        const mk_bytes = try Io.Dir.cwd().readFileAlloc(io, mk_path, gpa, .unlimited);
        defer gpa.free(mk_bytes);

        // Join backslash-continued lines
        var joined: std.ArrayList(u8) = .empty;
        defer joined.deinit(gpa);
        var i: usize = 0;
        while (i < mk_bytes.len) : (i += 1) {
            if (mk_bytes[i] == '\\' and i + 1 < mk_bytes.len and mk_bytes[i + 1] == '\n') {
                try joined.append(gpa, ' ');
                i += 1;
            } else {
                try joined.append(gpa, mk_bytes[i]);
            }
        }

        var line_it = std.mem.splitScalar(u8, joined.items, '\n');
        while (line_it.next()) |raw_line| {
            const no_comment = if (std.mem.indexOfScalar(u8, raw_line, '#')) |idx|
                raw_line[0..idx]
            else
                raw_line;
            const trimmed = std.mem.trim(u8, no_comment, " \t\r");
            if (!std.mem.startsWith(u8, trimmed, "gen-as-const-headers")) continue;
            const eq_idx = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
            const rhs = trimmed[eq_idx + 1 ..];
            var tok_it = std.mem.tokenizeAny(u8, rhs, " \t");
            while (tok_it.next()) |tok| {
                if (!std.mem.endsWith(u8, tok, ".sym")) continue;
                const stem = tok[0 .. tok.len - 4];
                // Find the highest-priority sysdir containing <tok>
                for (sysdirs) |search_dir| {
                    const candidate = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ search_dir, tok });
                    defer gpa.free(candidate);
                    if (fileExists(io, candidate)) {
                        try addSymIfNew(gpa, &sym_entries, stem, candidate);
                        break;
                    }
                }
            }
        }
    }

    for (common_sym_files) |sym_path| {
        const base = std.fs.path.basename(sym_path);
        const stem = base[0 .. base.len - 4];
        try addSymIfNew(gpa, &sym_entries, stem, sym_path);
    }

    var include_flags = try buildIncludeFlags(gpa, io, arch_out_dir, sysdirs);
    defer {
        for (include_flags.items) |f| gpa.free(f);
        include_flags.deinit(gpa);
    }

    // Build the --cc string for scripts/gen-as-const.py
    var cc_cmd: std.ArrayList(u8) = .empty;
    defer cc_cmd.deinit(gpa);
    try cc_cmd.print(
        gpa,
        "zig cc -target {s}",
        .{arch.zig_target},
    );
    for (arch.extra_cflags) |cf| {
        try cc_cmd.print(gpa, " {s}", .{cf});
    }
    try cc_cmd.appendSlice(
        gpa,
        " -std=gnu11 -fgnu89-inline -O2 -Wall -Wno-unused-command-line-argument -Wno-macro-redefined",
    );
    for (include_flags.items) |inc_f| {
        try cc_cmd.print(gpa, " {s}", .{inc_f});
    }
    try cc_cmd.print(
        gpa,
        " -include {s}/libc-modules.h -DMODULE_NAME=libc -include include/libc-symbols.h -DTOP_NAMESPACE=glibc -DGEN_AS_CONST_HEADERS",
        .{arch_out_dir},
    );

    const cc_arg = try std.fmt.allocPrint(gpa, "--cc={s}", .{cc_cmd.items});
    defer gpa.free(cc_arg);

    for (sym_entries.items) |entry| {
        const h_out = try runCmd(gpa, io, &.{
            "python3",
            "-B",
            "scripts/gen-as-const.py",
            cc_arg,
            entry.path,
        });
        defer gpa.free(h_out);

        const h_path = try std.fmt.allocPrint(gpa, "{s}/{s}.h", .{ arch_out_dir, entry.stem });
        defer gpa.free(h_path);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = h_path, .data = h_out });
        stats.headers += 1;
    }
}

fn generateErrlistAndSiglistAsm(
    gpa: std.mem.Allocator,
    io: Io,
    arch: archs.ArchConfig,
    arch_out_dir: []const u8,
    sysdirs: []const []const u8,
    stats: *GenStats,
) !void {
    const stdio_dir = try std.fmt.allocPrint(gpa, "{s}/stdio-common", .{arch_out_dir});
    defer gpa.free(stdio_dir);
    try Io.Dir.cwd().createDirPath(io, stdio_dir);

    const libc_modules_path = try std.fmt.allocPrint(gpa, "{s}/libc-modules.h", .{arch_out_dir});
    defer gpa.free(libc_modules_path);

    var include_flags = try buildIncludeFlags(gpa, io, arch_out_dir, sysdirs);
    defer {
        for (include_flags.items) |f| gpa.free(f);
        include_flags.deinit(gpa);
    }

    const Spec = struct {
        c_file: []const u8,
        out_name: []const u8,
        shared: bool,
    };
    const specs = [_]Spec{
        .{ .c_file = "stdio-common/errlist-data-gen.c", .out_name = "errlist-data-aux.S", .shared = false },
        .{ .c_file = "stdio-common/errlist-data-gen.c", .out_name = "errlist-data-aux-shared.S", .shared = true },
        .{ .c_file = "stdio-common/siglist-gen.c", .out_name = "siglist-aux.S", .shared = false },
        .{ .c_file = "stdio-common/siglist-gen.c", .out_name = "siglist-aux-shared.S", .shared = true },
    };

    for (specs) |spec| {
        const out_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ stdio_dir, spec.out_name });
        defer gpa.free(out_path);

        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(gpa);
        try argv.appendSlice(gpa, &.{
            "zig",
            "cc",
            "-target",
            arch.zig_target,
        });
        try argv.appendSlice(gpa, arch.extra_cflags);
        try argv.appendSlice(gpa, &.{
            "-std=gnu11",
            "-fgnu89-inline",
            "-O2",
            "-fno-common",
            "-Wno-unused-command-line-argument",
            "-Wno-macro-redefined",
        });
        try argv.appendSlice(gpa, include_flags.items);
        try argv.appendSlice(gpa, &.{
            "-Istdio-common",
            "-include",
            libc_modules_path,
            "-DMODULE_NAME=libc",
            "-include",
            "include/libc-symbols.h",
            "-DTOP_NAMESPACE=glibc",
        });
        if (spec.shared) {
            try argv.appendSlice(gpa, &.{ "-DPIC", "-DSHARED" });
        }
        try argv.appendSlice(gpa, &.{
            "-S",
            spec.c_file,
            "-o",
            out_path,
        });

        const out = try runCmd(gpa, io, argv.items);
        gpa.free(out);
        stats.asm_sources += 1;
    }
}

fn generateSyscalls(
    gpa: std.mem.Allocator,
    io: Io,
    arch_out_dir: []const u8,
    sysdirs: []const []const u8,
    stats: *GenStats,
) !void {
    const syscalls_dir = try std.fmt.allocPrint(gpa, "{s}/syscalls", .{arch_out_dir});
    defer gpa.free(syscalls_dir);
    try Io.Dir.cwd().createDirPath(io, syscalls_dir);

    // 1. Parse arch-syscall.h in sysdirs to collect defined __NR_<syscall> names
    var nr_defined: std.StringHashMapUnmanaged(void) = .empty;
    defer {
        var key_it = nr_defined.keyIterator();
        while (key_it.next()) |k| gpa.free(k.*);
        nr_defined.deinit(gpa);
    }

    for (sysdirs) |sdir| {
        const p = try std.fmt.allocPrint(gpa, "{s}/arch-syscall.h", .{sdir});
        defer gpa.free(p);
        if (!fileExists(io, p)) continue;

        const bytes = try Io.Dir.cwd().readFileAlloc(io, p, gpa, .unlimited);
        defer gpa.free(bytes);

        var line_it = std.mem.splitScalar(u8, bytes, '\n');
        while (line_it.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (!std.mem.startsWith(u8, trimmed, "#define __NR_")) continue;
            const after = trimmed["#define __NR_".len..];
            var tok_it = std.mem.tokenizeAny(u8, after, " \t");
            const name = tok_it.next() orelse continue;
            if (!nr_defined.contains(name)) {
                try nr_defined.put(gpa, try gpa.dupe(u8, name), {});
            }
        }
    }

    // 2. Parse syscalls.list in sysdirs priority order ( matching sysdeps/unix/make-syscalls.sh )
    var handled_files: std.StringHashMapUnmanaged(void) = .empty;
    defer {
        var key_it = handled_files.keyIterator();
        while (key_it.next()) |k| gpa.free(k.*);
        handled_files.deinit(gpa);
    }

    var sysd_syscalls: std.ArrayList(u8) = .empty;
    defer sysd_syscalls.deinit(gpa);

    var stub_names: std.ArrayList([]const u8) = .empty;
    defer {
        for (stub_names.items) |s| gpa.free(s);
        stub_names.deinit(gpa);
    }

    for (sysdirs) |thisdir| {
        const list_path = try std.fmt.allocPrint(gpa, "{s}/syscalls.list", .{thisdir});
        defer gpa.free(list_path);
        if (!fileExists(io, list_path)) continue;

        const bytes = try Io.Dir.cwd().readFileAlloc(io, list_path, gpa, .unlimited);
        defer gpa.free(bytes);

        var line_it = std.mem.splitScalar(u8, bytes, '\n');
        while (line_it.next()) |raw_line| {
            const no_comment = if (std.mem.indexOfScalar(u8, raw_line, '#')) |idx|
                raw_line[0..idx]
            else
                raw_line;
            const trimmed = std.mem.trim(u8, no_comment, " \t\r");
            if (trimmed.len == 0) continue;

            var tok_it = std.mem.tokenizeAny(u8, trimmed, " \t");
            const file = tok_it.next() orelse continue;
            const caller = tok_it.next() orelse continue;
            const syscall = tok_it.next() orelse continue;
            const args = tok_it.next() orelse continue;
            const strong = tok_it.next() orelse continue;
            const weak_rest = std.mem.trim(u8, tok_it.rest(), " \t");

            // Skip if already handled by an earlier syscalls.list
            if (handled_files.contains(file)) continue;

            // Check if overridden by an explicit .c, .S, or .s file in a higher-priority sysdir
            var overridden = false;
            for (sysdirs) |dir| {
                if (std.mem.eql(u8, dir, thisdir)) break;
                for ([_][]const u8{ ".c", ".S", ".s" }) |ext| {
                    const candidate = try std.fmt.allocPrint(gpa, "{s}/{s}{s}", .{ dir, file, ext });
                    defer gpa.free(candidate);
                    if (fileExists(io, candidate)) {
                        overridden = true;
                        break;
                    }
                }
                if (overridden) break;
            }
            if (overridden) continue;

            // Check if caller routine is overridden in a higher-priority sysdir
            if (!std.mem.eql(u8, caller, "-") and !std.mem.eql(u8, caller, "EXTRA")) {
                var caller_overridden = false;
                for (sysdirs) |dir| {
                    if (std.mem.eql(u8, dir, thisdir)) break;
                    for ([_][]const u8{ ".c", ".S", ".s" }) |ext| {
                        const candidate = try std.fmt.allocPrint(gpa, "{s}/{s}{s}", .{ dir, caller, ext });
                        defer gpa.free(candidate);
                        if (fileExists(io, candidate)) {
                            caller_overridden = true;
                            break;
                        }
                    }
                    if (caller_overridden) break;
                }
                if (caller_overridden) continue;
            }

            try handled_files.put(gpa, try gpa.dupe(u8, file), {});

            const is_defined_syscall = nr_defined.contains(syscall);
            if (!is_defined_syscall and std.mem.eql(u8, syscall, "-")) {
                // Stub syscall
                try stub_names.append(gpa, try gpa.dupe(u8, strong));
                var w_it = std.mem.tokenizeAny(u8, weak_rest, " \t");
                while (w_it.next()) |w| {
                    if (std.mem.indexOfScalar(u8, w, '@') == null) {
                        try stub_names.append(gpa, try gpa.dupe(u8, w));
                    }
                }
                continue;
            }
            if (!is_defined_syscall) continue;

            // Parse args (e.g., `i:pii`, `Ci:s`, `Ei:ip`, `Vi:p`)
            var cancellable: u8 = '0';
            var noerrno: u8 = '0';
            var errval: u8 = '0';
            for (args) |ch| {
                if (ch == ':') break;
                switch (ch) {
                    'C' => cancellable = '1',
                    'V' => noerrno = '1',
                    'E' => errval = '1',
                    else => {},
                }
            }
            const colon_idx = std.mem.indexOfScalar(u8, args, ':');
            const after_colon = if (colon_idx) |idx| args[idx + 1 ..] else "";
            const nargs = after_colon.len;

            var asm_buf: std.ArrayList(u8) = .empty;
            defer asm_buf.deinit(gpa);

            try asm_buf.print(
                gpa,
                \\/* Generated by Zig glibc generator from {s}/syscalls.list */
                \\#define SYSCALL_NAME {s}
                \\#define SYSCALL_NARGS {d}
                \\#define SYSCALL_SYMBOL {s}
                \\#define SYSCALL_CANCELLABLE {c}
                \\#define SYSCALL_NOERRNO {c}
                \\#define SYSCALL_ERRVAL {c}
                \\#include <syscall-template.S>
                \\
            ,
                .{ thisdir, syscall, nargs, strong, cancellable, noerrno, errval },
            );

            var w_it = std.mem.tokenizeAny(u8, weak_rest, " \t");
            while (w_it.next()) |name| {
                if (std.mem.indexOfScalar(u8, name, '@')) |at_idx| {
                    const base = name[0..at_idx];
                    const rest_ver = name[at_idx + 1 ..];
                    if (std.mem.startsWith(u8, rest_ver, "@")) {
                        // Default versioned symbol: base@@ver
                        const ver = rest_ver[1..];
                        var ver_ob: std.ArrayList(u8) = .empty;
                        defer ver_ob.deinit(gpa);
                        for (ver) |c| {
                            try ver_ob.append(gpa, if (c == '.') '_' else c);
                        }
                        try asm_buf.print(
                            gpa,
                            \\#if SHLIB_COMPAT (libc, GLIBC_2_0, {s})
                            \\strong_alias ({s}, __{s}_{s})
                            \\default_symbol_version (__{s}_{s}, {s}, {s})
                            \\#else
                            \\weak_alias ({s}, {s})
                            \\hidden_weak ({s})
                            \\#endif
                            \\
                        ,
                            .{ ver_ob.items, strong, base, ver_ob.items, base, ver_ob.items, base, ver, strong, base, base },
                        );
                    } else {
                        // Compat versioned symbol: base@ver
                        var ver_ob: std.ArrayList(u8) = .empty;
                        defer ver_ob.deinit(gpa);
                        for (rest_ver) |c| {
                            try ver_ob.append(gpa, if (c == '.') '_' else c);
                        }
                        try asm_buf.print(
                            gpa,
                            \\#if SHLIB_COMPAT (libc, {s}, {s})
                            \\strong_alias ({s}, __{s}_{s})
                            \\compat_symbol (libc, __{s}_{s}, {s}, {s})
                            \\#endif
                            \\
                        ,
                            .{ ver_ob.items, ver_ob.items, strong, base, ver_ob.items, base, ver_ob.items, base, rest_ver },
                        );
                    }
                } else if (std.mem.startsWith(u8, name, "!")) {
                    const strong_target = name[1..];
                    try asm_buf.print(
                        gpa,
                        \\strong_alias ({s}, {s})
                        \\hidden_def ({s})
                        \\
                    ,
                        .{ strong, strong_target, strong_target },
                    );
                } else {
                    try asm_buf.print(
                        gpa,
                        \\weak_alias ({s}, {s})
                        \\hidden_weak ({s})
                        \\
                    ,
                        .{ strong, name, name },
                    );
                }
            }
            try asm_buf.print(gpa, "hidden_def ({s})\n", .{strong});

            const asm_path = try std.fmt.allocPrint(gpa, "{s}/{s}.S", .{ syscalls_dir, file });
            defer gpa.free(asm_path);
            try Io.Dir.cwd().writeFile(io, .{ .sub_path = asm_path, .data = asm_buf.items });
            stats.asm_sources += 1;

            try sysd_syscalls.print(gpa, "unix-syscalls += {s}\n", .{file});
        }
    }

    if (stub_names.items.len > 0) {
        var stub_c: std.ArrayList(u8) = .empty;
        defer stub_c.deinit(gpa);
        try stub_c.appendSlice(gpa,
            \\#define _LIBC_REENTRANT
            \\#include <errno.h>
            \\long int _no_syscall (void)
            \\{ __set_errno (ENOSYS); return -1L; }
            \\
        );
        for (stub_names.items) |s| {
            try stub_c.print(
                gpa,
                "weak_alias (_no_syscall, {s})\nstub_warning ({s})\nweak_alias (_no_syscall, __GI_{s})\n",
                .{ s, s, s },
            );
        }
        const stub_c_path = try std.fmt.allocPrint(gpa, "{s}/stub-syscalls.c", .{syscalls_dir});
        defer gpa.free(stub_c_path);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = stub_c_path, .data = stub_c.items });
        stats.c_sources += 1;
    }

    const sysd_syscalls_path = try std.fmt.allocPrint(gpa, "{s}/sysd-syscalls", .{arch_out_dir});
    defer gpa.free(sysd_syscalls_path);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = sysd_syscalls_path, .data = sysd_syscalls.items });
}

pub fn generateForArch(
    gpa: std.mem.Allocator,
    io: Io,
    arch: archs.ArchConfig,
    base_out_dir: []const u8,
    common: *const CommonTargetIndepFiles,
) !GenStats {
    var stats: GenStats = .{};
    const arch_out_dir = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base_out_dir, arch.name });
    defer gpa.free(arch_out_dir);
    try Io.Dir.cwd().createDirPath(io, arch_out_dir);

    const sysdirs = try archs.resolveSysdirs(gpa, io, arch);
    defer {
        for (sysdirs) |s| gpa.free(s);
        gpa.free(sysdirs);
    }

    // Write sysdirs.txt manifest
    {
        var sbuf: std.ArrayList(u8) = .empty;
        defer sbuf.deinit(gpa);
        for (sysdirs) |sdir| {
            try sbuf.appendSlice(gpa, sdir);
            try sbuf.append(gpa, '\n');
        }
        const sysdirs_path = try std.fmt.allocPrint(gpa, "{s}/sysdirs.txt", .{arch_out_dir});
        defer gpa.free(sysdirs_path);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = sysdirs_path, .data = sbuf.items });
    }

    // 1. Generate config.h
    try generateConfigH(gpa, io, arch, arch_out_dir);
    stats.headers += 1;

    // 2. Generate shlib-versions.v, soversions.i, runtime-linker.h, libc-modules.h,
    //    gnu/lib-names*.h, gnu/stubs*.h, Versions.*, abi-versions.h, first-versions.h,
    //    ldbl-compat-choose.h, sysd-versions, and all *.map linker scripts
    try generateShlibAndVersions(gpa, io, arch, arch_out_dir, sysdirs, &stats);

    // 3. Generate other headers & C sources (dl-tunable-list.h, libc-abis.h, gcc-macros.h,
    //    abi-tag.h, version-info.h, trusted-dirs.h, posix-conf-vars-def.h, C-translit.h,
    //    msgs.h, bits/syscall.h, intl/plural.c, nss/db-*.c)
    try generateOtherHeadersAndSources(gpa, io, arch, arch_out_dir, sysdirs, common, &stats);

    // 4. Generate assembly constant headers (*.sym -> *.h via scripts/gen-as-const.py)
    try generateAsConstHeaders(gpa, io, arch, arch_out_dir, sysdirs, &stats);

    // 5. Generate math template C sources (math/*.c)
    stats.c_sources += try math_data.generateMathSources(gpa, io, arch_out_dir, sysdirs);

    // 6. Generate errlist-data-aux*.S and siglist-aux*.S assembly files
    try generateErrlistAndSiglistAsm(gpa, io, arch, arch_out_dir, sysdirs, &stats);

    // 7. Generate syscall wrapper assembly files (syscalls/*.S)
    try generateSyscalls(gpa, io, arch_out_dir, sysdirs, &stats);

    return stats;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var target_arch: []const u8 = "all";
    var out_dir: []const u8 = "zig-out/generated";
    var list_only = false;

    var arg_it = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer arg_it.deinit();
    _ = arg_it.next(); // skip argv[0]

    while (arg_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--list-archs")) {
            list_only = true;
        } else if (std.mem.startsWith(u8, arg, "--arch=")) {
            target_arch = arg["--arch=".len..];
        } else if (std.mem.eql(u8, arg, "--arch")) {
            target_arch = arg_it.next() orelse return error.MissingArchArg;
        } else if (std.mem.startsWith(u8, arg, "--out-dir=")) {
            out_dir = arg["--out-dir=".len..];
        } else if (std.mem.eql(u8, arg, "--out-dir")) {
            out_dir = arg_it.next() orelse return error.MissingOutDirArg;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            std.debug.print(
                \\Usage: glibc-gen [options]
                \\  --arch=<arch|all>     Target architecture or 'all' (default: all)
                \\  --out-dir=<dir>       Output directory (default: zig-out/generated)
                \\  --list-archs          List all 22 Zig-supported glibc architectures
                \\
            , .{});
            return;
        }
    }

    if (list_only) {
        std.debug.print("Supported glibc architectures (supported by zig cc 0.17.0):\n", .{});
        for (archs.supported_archs) |a| {
            std.debug.print("  {s:<16} zig_target={s:<26} triple={s}\n", .{
                a.name,
                a.zig_target,
                a.config_triple,
            });
        }
        return;
    }

    var common = try CommonTargetIndepFiles.init(gpa, io, out_dir);
    defer common.deinit(gpa);

    if (std.mem.eql(u8, target_arch, "all")) {
        var total: GenStats = .{};
        for (archs.supported_archs, 0..) |arch, idx| {
            std.debug.print("[{d}/{d}] Generating glibc files for {s} ({s})...\n", .{
                idx + 1,
                archs.supported_archs.len,
                arch.name,
                arch.zig_target,
            });
            const s = try generateForArch(gpa, io, arch, out_dir, &common);
            std.debug.print("  -> {d} headers (.h), {d} C sources (.c), {d} asm files (.S), {d} linker scripts (.map)\n", .{
                s.headers,
                s.c_sources,
                s.asm_sources,
                s.map_files,
            });
            total.headers += s.headers;
            total.c_sources += s.c_sources;
            total.asm_sources += s.asm_sources;
            total.map_files += s.map_files;
        }
        std.debug.print(
            "\nCompleted all {d} architectures in '{s}':\n  Total: {d} headers, {d} C sources, {d} asm files, {d} .map files\n",
            .{ archs.supported_archs.len, out_dir, total.headers, total.c_sources, total.asm_sources, total.map_files },
        );
    } else {
        const arch = archs.findArch(target_arch) orelse {
            std.debug.print("Unknown architecture '{s}'. Use --list-archs to see supported targets.\n", .{target_arch});
            return error.UnknownArchitecture;
        };
        std.debug.print("Generating glibc files for {s} ({s})...\n", .{ arch.name, arch.zig_target });
        const s = try generateForArch(gpa, io, arch, out_dir, &common);
        std.debug.print("  -> {d} headers (.h), {d} C sources (.c), {d} asm files (.S), {d} linker scripts (.map) in {s}/{s}\n", .{
            s.headers,
            s.c_sources,
            s.asm_sources,
            s.map_files,
            out_dir,
            arch.name,
        });
    }
}

test "resolveSysdirs for all supported architectures" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    for (archs.supported_archs) |arch| {
        const sysdirs = try archs.resolveSysdirs(gpa, io, arch);
        defer {
            for (sysdirs) |s| gpa.free(s);
            gpa.free(sysdirs);
        }
        try std.testing.expect(sysdirs.len > 5);
    }
}
