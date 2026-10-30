const std = @import("std");
const Io = std.Io;

pub const gen_libm_calls = [_][]const u8{
    "cabsF",
    "cargF",
    "cimagF",
    "conjF",
    "crealF",
    "e_exp2F",
    "e_scalbF",
    "k_casinhF",
    "s_acospiF",
    "s_asinpiF",
    "s_atan2piF",
    "s_atanpiF",
    "s_cacosF",
    "s_cacoshF",
    "s_canonicalizeF",
    "s_casinF",
    "s_casinhF",
    "s_catanF",
    "s_catanhF",
    "s_ccosF",
    "s_ccoshF",
    "s_cexpF",
    "s_clog10F",
    "s_clogF",
    "s_compoundnF",
    "s_cospiF",
    "s_cpowF",
    "s_cprojF",
    "s_csinF",
    "s_csinhF",
    "s_csqrtF",
    "s_ctanF",
    "s_ctanhF",
    "s_exp10m1F",
    "s_exp2m1F",
    "s_fdimF",
    "s_fmaxF",
    "s_fmaximumF",
    "s_fmaximum_magF",
    "s_fmaximum_mag_numF",
    "s_fmaximum_numF",
    "s_fmaxmagF",
    "s_fminF",
    "s_fminimumF",
    "s_fminimum_magF",
    "s_fminimum_mag_numF",
    "s_fminimum_numF",
    "s_fminmagF",
    "s_iseqsigF",
    "s_log10p1F",
    "s_log2p1F",
    "s_nanF",
    "s_nextdownF",
    "s_pownF",
    "s_powrF",
    "s_rootnF",
    "s_rsqrtF",
    "s_significandF",
    "s_sinpiF",
    "s_tanpiF",
    "w_acosF",
    "w_acoshF",
    "w_asinF",
    "w_atan2F",
    "w_atanhF",
    "w_coshF",
    "w_exp10F",
    "w_exp2F",
    "w_expF",
    "w_fmodF",
    "w_hypotF",
    "w_ilogbF",
    "w_j0F",
    "w_j1F",
    "w_jnF",
    "w_lgammaF",
    "w_lgammaF_r",
    "w_llogbF",
    "w_log10F",
    "w_log1pF",
    "w_log2F",
    "w_logF",
    "w_powF",
    "w_remainderF",
    "w_scalbF",
    "w_scalblnF",
    "w_sinhF",
    "w_sqrtF",
    "w_tgammaF",
    // gen-calls
    "s_ldexpF",
};

pub const ppc64le_f128_ifunc_routines = [_][]const u8{
    "e_acosf128",
    "e_acoshf128",
    "e_asinf128",
    "e_atan2f128",
    "e_atanhf128",
    "e_coshf128",
    "e_expf128",
    "e_fmodf128",
    "e_hypotf128",
    "e_j0f128",
    "e_j1f128",
    "e_jnf128",
    "e_lgammaf128_r",
    "e_logf128",
    "e_log10f128",
    "e_powf128",
    "e_remainderf128",
    "e_sinhf128",
    "e_sqrtf128",
    "e_gammaf128_r",
    "e_ilogbf128",
    "k_tanf128",
    "s_asinhf128",
    "s_atanf128",
    "s_cbrtf128",
    "s_ceilf128",
    "s_compoundnf128",
    "s_cosf128",
    "s_erff128",
    "s_exp10m1f128",
    "s_exp2m1f128",
    "s_expm1f128",
    "s_fabsf128",
    "s_floorf128",
    "s_log1pf128",
    "s_logbf128",
    "s_rintf128",
    "s_scalblnf128",
    "s_sinf128",
    "s_tanf128",
    "s_tanhf128",
    "s_truncf128",
    "s_remquof128",
    "e_log2f128",
    "s_roundf128",
    "s_nearbyintf128",
    "s_sincosf128",
    "s_fmaf128",
    "s_lrintf128",
    "s_llrintf128",
    "s_lroundf128",
    "s_llroundf128",
    "e_exp10f128",
    "s_modff128",
    "s_scalbnf128",
    "s_frexpf128",
    "s_ldexpf128",
    "m_modff128",
    "m_scalbnf128",
    "m_frexpf128",
    "m_ldexpf128",
    "x2y2m1f128",
    "gamma_productf128",
    "lgamma_negf128",
    "lgamma_productf128",
    "s_roundevenf128",
    "cargf128",
    "conjf128",
    "cimagf128",
    "crealf128",
    "cabsf128",
    "e_scalbf128",
    "s_cacosf128",
    "s_cacoshf128",
    "s_ccosf128",
    "s_ccoshf128",
    "s_casinf128",
    "s_csinf128",
    "s_casinhf128",
    "k_casinhf128",
    "s_csinhf128",
    "s_catanhf128",
    "s_catanf128",
    "s_ctanf128",
    "s_ctanhf128",
    "s_cexpf128",
    "s_clogf128",
    "s_cprojf128",
    "s_csqrtf128",
    "s_cpowf128",
    "s_clog10f128",
    "s_fdimf128",
    "s_fmaxf128",
    "s_fminf128",
    "w_ilogbf128",
    "w_llogbf128",
    "w_log1pf128",
    "w_scalblnf128",
    "w_acosf128",
    "w_acoshf128",
    "w_asinf128",
    "w_atan2f128",
    "w_atanhf128",
    "w_coshf128",
    "w_exp10f128",
    "w_exp2f128",
    "w_fmodf128",
    "w_hypotf128",
    "w_j0f128",
    "w_j1f128",
    "w_jnf128",
    "w_logf128",
    "w_log10f128",
    "w_log2f128",
    "w_powf128",
    "w_remainderf128",
    "w_scalbf128",
    "w_sinhf128",
    "w_sqrtf128",
    "w_tgammaf128",
    "w_lgammaf128",
    "w_lgammaf128_r",
    "w_expf128",
    "e_exp2f128",
    "k_sinf128",
    "k_cosf128",
    "k_sincosf128",
    "e_rem_pio2f128",
};

pub const MathType = struct {
    name: []const u8,
    suffix: []const u8,
};

fn hasSysdir(sysdirs: []const []const u8, needle: []const u8) bool {
    for (sysdirs) |dir| {
        if (std.mem.eql(u8, dir, needle)) return true;
    }
    return false;
}

fn hasSysdirPrefix(sysdirs: []const []const u8, prefix: []const u8) bool {
    for (sysdirs) |dir| {
        if (std.mem.startsWith(u8, dir, prefix)) return true;
    }
    return false;
}

/// Generate all math template `.c` files in `<arch_out_dir>/math/` based on resolved sysdirs.
/// Returns the number of generated `.c` files.
pub fn generateMathSources(
    gpa: std.mem.Allocator,
    io: Io,
    arch_out_dir: []const u8,
    sysdirs: []const []const u8,
) !usize {
    const math_dir = try std.fmt.allocPrint(gpa, "{s}/math", .{arch_out_dir});
    defer gpa.free(math_dir);
    try Io.Dir.cwd().createDirPath(io, math_dir);

    // Determine active floating-point types from sysdirs (matching sysdeps/ieee754/*/Makefile)
    const long_double_fcts = hasSysdirPrefix(sysdirs, "sysdeps/ieee754/ldbl-96") or
        hasSysdirPrefix(sysdirs, "sysdeps/ieee754/ldbl-128") or
        hasSysdirPrefix(sysdirs, "sysdeps/ieee754/ldbl-opt");
    const float128_fcts = hasSysdir(sysdirs, "sysdeps/ieee754/float128");

    var types_buf: [4]MathType = undefined;
    var types_len: usize = 0;
    if (float128_fcts) {
        types_buf[types_len] = .{ .name = "float128", .suffix = "f128" };
        types_len += 1;
    }
    if (long_double_fcts) {
        types_buf[types_len] = .{ .name = "ldouble", .suffix = "l" };
        types_len += 1;
    }
    types_buf[types_len] = .{ .name = "double", .suffix = "" };
    types_len += 1;
    types_buf[types_len] = .{ .name = "float", .suffix = "f" };
    types_len += 1;

    const active_types = types_buf[0..types_len];
    var count: usize = 0;

    for (gen_libm_calls) |gcall| {
        const f_idx = std.mem.indexOfScalar(u8, gcall, 'F') orelse unreachable;
        const prefix = gcall[0..f_idx];
        const post = gcall[f_idx + 1 ..];

        const func_name = try std.fmt.allocPrint(gpa, "{s}{s}", .{ prefix, post });
        defer gpa.free(func_name);

        for (active_types) |mtype| {
            const file_path = try std.fmt.allocPrint(
                gpa,
                "{s}/{s}{s}{s}.c",
                .{ math_dir, prefix, mtype.suffix, post },
            );
            defer gpa.free(file_path);

            const content = try std.fmt.allocPrint(
                gpa,
                "#include <math-type-macros-{s}.h>\n#include <{s}_template.c>\n",
                .{ mtype.name, func_name },
            );
            defer gpa.free(content);

            try Io.Dir.cwd().writeFile(io, .{ .sub_path = file_path, .data = content });
            count += 1;

            // Also generate m_ldexp<suffix>.c for shared libm builds
            if (std.mem.eql(u8, gcall, "s_ldexpF")) {
                const m_path = try std.fmt.allocPrint(
                    gpa,
                    "{s}/m_ldexp{s}.c",
                    .{ math_dir, mtype.suffix },
                );
                defer gpa.free(m_path);
                try Io.Dir.cwd().writeFile(io, .{ .sub_path = m_path, .data = content });
                count += 1;
            }
        }
    }

    // Generate powerpc64le multiarch float128 ifunc and power9 wrapper C sources
    if (hasSysdir(sysdirs, "sysdeps/powerpc/powerpc64/le/fpu/multiarch")) {
        for (ppc64le_f128_ifunc_routines) |gcall| {
            const is_m = std.mem.startsWith(u8, gcall, "m_");
            const ifile = if (is_m)
                try std.fmt.allocPrint(gpa, "s_{s}", .{gcall[2..]})
            else
                try gpa.dupe(u8, gcall);
            defer gpa.free(ifile);

            const p9_path = try std.fmt.allocPrint(gpa, "{s}/{s}-power9.c", .{ math_dir, gcall });
            defer gpa.free(p9_path);
            const p9_content = try std.fmt.allocPrint(gpa, "#include <{s}.c>\n", .{ifile});
            defer gpa.free(p9_content);
            try Io.Dir.cwd().writeFile(io, .{ .sub_path = p9_path, .data = p9_content });
            count += 1;

            // Replicate shell logic from sysdeps/powerpc/powerpc64/le/fpu/multiarch/Makefile:
            // name="${gcall##?_}"
            // pfx="${gcall%%_*}"
            var name: []const u8 = if (gcall.len > 2 and gcall[1] == '_') gcall[2..] else gcall;
            const first_underscore = std.mem.indexOfScalar(u8, gcall, '_');
            var raw_pfx: []const u8 = if (first_underscore) |idx| gcall[0..idx] else gcall;
            if (is_m) {
                raw_pfx = "s";
            }
            const pfx: []const u8 = if (raw_pfx.len != 1)
                ""
            else if (std.mem.eql(u8, raw_pfx, "e"))
                "_e"
            else if (std.mem.eql(u8, raw_pfx, "k"))
                "_k"
            else if (std.mem.eql(u8, raw_pfx, "s"))
                "_s"
            else if (std.mem.eql(u8, raw_pfx, "w"))
                "_w"
            else
                "";

            var r_upper: []const u8 = "";
            var r_lower: []const u8 = "";
            if (std.mem.endsWith(u8, name, "_r")) {
                r_upper = "_R";
                r_lower = "_r";
                name = name[0 .. name.len - 2];
            }
            if (std.mem.endsWith(u8, name, "f128")) {
                name = name[0 .. name.len - 4];
            }

            const ifunc_path = try std.fmt.allocPrint(gpa, "{s}/{s}-ifunc.c", .{ math_dir, gcall });
            defer gpa.free(ifunc_path);
            const ifunc_content = try std.fmt.allocPrint(
                gpa,
                \\#include <float128-ifunc.h>
                \\#ifndef DECL_ALIAS{s}_{s}{s}
                \\# define DECL_ALIAS{s}_{s}{s}(f) DECL_ALIAS{s}{s} (f)
                \\#endif
                \\#ifndef GEN_COMPAT{s}_{s}{s}
                \\# define GEN_COMPAT{s}_{s}{s}(f)
                \\#endif
                \\DECL_ALIAS{s}_{s}{s} ({s});
                \\GEN_COMPAT{s}_{s}{s} ({s});
                \\
            ,
                .{
                    pfx, name, r_lower,
                    pfx, name, r_lower, r_upper, pfx,
                    pfx, name, r_lower,
                    pfx, name, r_lower,
                    pfx, name, r_lower, name,
                    pfx, name, r_lower, name,
                },
            );
            defer gpa.free(ifunc_content);
            try Io.Dir.cwd().writeFile(io, .{ .sub_path = ifunc_path, .data = ifunc_content });
            count += 1;
        }
    }

    return count;
}
