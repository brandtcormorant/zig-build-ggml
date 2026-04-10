const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const ggml = b.dependency("ggml", .{});

    const os = target.result.os.tag;
    const abi = target.result.abi;
    const arch = target.result.cpu.arch;
    const is_darwin = os.isDarwin();
    const is_android = abi.isAndroid();
    const is_linux = os == .linux and !is_android;
    const is_freebsd = os == .freebsd;
    const is_netbsd = os == .netbsd;
    const is_openbsd = os == .openbsd;
    const is_windows = os == .windows;


    const opt_native = b.option(bool, "native", "Optimize for current CPU (-march=native)") orelse false;

    const opt_cpu = b.option(bool, "cpu-backend", "Enable CPU backend") orelse true;
    const opt_metal = b.option(bool, "metal", "Enable Metal backend") orelse (os == .macos or os == .ios);
    const opt_metal_embed = b.option(bool, "metal-embed-library", "Embed Metal shader library") orelse opt_metal;

    const opt_accelerate = b.option(bool, "accelerate", "Use Apple Accelerate framework") orelse is_darwin;
    const opt_llamafile = b.option(bool, "llamafile", "Enable llamafile SGEMM kernels") orelse false;
    const opt_cpu_repack = b.option(bool, "cpu-repack", "Enable runtime weight repacking") orelse true;

    const opt_sse42 = b.option(bool, "sse42", "Enable SSE 4.2") orelse false;
    const opt_avx = b.option(bool, "avx", "Enable AVX") orelse false;
    const opt_avx2 = b.option(bool, "avx2", "Enable AVX2") orelse false;
    const opt_fma = b.option(bool, "fma", "Enable FMA") orelse false;
    const opt_f16c = b.option(bool, "f16c", "Enable F16C") orelse false;
    const opt_bmi2 = b.option(bool, "bmi2", "Enable BMI2") orelse false;
    const opt_avx_vnni = b.option(bool, "avx-vnni", "Enable AVX-VNNI") orelse false;
    const opt_avx512 = b.option(bool, "avx512", "Enable AVX-512F") orelse false;
    const opt_avx512_vbmi = b.option(bool, "avx512-vbmi", "Enable AVX-512 VBMI") orelse false;
    const opt_avx512_vnni = b.option(bool, "avx512-vnni", "Enable AVX-512 VNNI") orelse false;
    const opt_avx512_bf16 = b.option(bool, "avx512-bf16", "Enable AVX-512 BF16") orelse false;
    const opt_amx_tile = b.option(bool, "amx-tile", "Enable AMX-TILE") orelse false;
    const opt_amx_int8 = b.option(bool, "amx-int8", "Enable AMX-INT8") orelse false;
    const opt_amx_bf16 = b.option(bool, "amx-bf16", "Enable AMX-BF16") orelse false;

    const opt_sysroot = b.option([]const u8, "sysroot", "System root for cross-compilation (iOS SDK path, Android NDK sysroot path)");

    const lib = b.addLibrary(.{
        .name = "ggml",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });

    const mod = lib.root_module;

    mod.addIncludePath(ggml.path("include"));
    mod.addIncludePath(ggml.path("src"));

    // ── Platform flags ───────────────────────────────────────

    var platform_flags: [8][]const u8 = undefined;
    var platform_flag_count: usize = 0;

    if (opt_sysroot) |sr| {
        mod.addSystemIncludePath(.{ .cwd_relative = b.fmt("{s}/usr/include", .{sr}) });
        if (is_darwin) {
            mod.addFrameworkPath(.{ .cwd_relative = b.fmt("{s}/System/Library/Frameworks", .{sr}) });
        }
        if (is_android) {
            const android_triple = switch (arch) {
                .aarch64 => "aarch64-linux-android",
                .x86_64 => "x86_64-linux-android",
                .x86 => "i686-linux-android",
                .arm, .thumb => "arm-linux-androideabi",
                else => "aarch64-linux-android",
            };
            mod.addSystemIncludePath(.{ .cwd_relative = b.fmt("{s}/usr/include/{s}", .{ sr, android_triple }) });
        }
    }

    if (is_openbsd) {
        platform_flags[platform_flag_count] = "-D_XOPEN_SOURCE=700";
        platform_flag_count += 1;
    } else if (!is_android) {
        platform_flags[platform_flag_count] = "-D_XOPEN_SOURCE=600";
        platform_flag_count += 1;
    }
    if (os == .linux) {
        platform_flags[platform_flag_count] = "-D_GNU_SOURCE";
        platform_flag_count += 1;
    }
    if (is_darwin) {
        platform_flags[platform_flag_count] = "-D_DARWIN_C_SOURCE";
        platform_flag_count += 1;
    }
    if (is_freebsd) {
        platform_flags[platform_flag_count] = "-D__BSD_VISIBLE";
        platform_flag_count += 1;
    }
    if (is_netbsd) {
        platform_flags[platform_flag_count] = "-D_NETBSD_SOURCE";
        platform_flag_count += 1;
    }
    if (is_openbsd) {
        platform_flags[platform_flag_count] = "-D_BSD_SOURCE";
        platform_flag_count += 1;
    }
    if (is_windows) {
        platform_flags[platform_flag_count] = "-D_CRT_SECURE_NO_WARNINGS";
        platform_flag_count += 1;
    }

    const pf = platform_flags[0..platform_flag_count];

    // ── ggml-base ────────────────────────────────────────────

    const base_version_flag = "-DGGML_VERSION=\"0.9.11\"";
    const base_commit_flag = "-DGGML_COMMIT=\"unknown\"";
    const sched_copies_flag = "-DGGML_SCHED_MAX_COPIES=4";

    {
        var c_flags_buf: [16][]const u8 = undefined;
        var c_count: usize = 0;
        c_flags_buf[c_count] = "-std=c11";
        c_count += 1;
        c_flags_buf[c_count] = base_version_flag;
        c_count += 1;
        c_flags_buf[c_count] = base_commit_flag;
        c_count += 1;
        c_flags_buf[c_count] = sched_copies_flag;
        c_count += 1;
        for (pf) |f| {
            c_flags_buf[c_count] = f;
            c_count += 1;
        }
        const c_flags = c_flags_buf[0..c_count];

        mod.addCSourceFiles(.{
            .root = ggml.path("src"),
            .files = &.{
                "ggml.c",
                "ggml-alloc.c",
                "ggml-quants.c",
            },
            .flags = c_flags,
        });
    }

    {
        var cpp_flags_buf: [16][]const u8 = undefined;
        var cpp_count: usize = 0;
        cpp_flags_buf[cpp_count] = "-std=c++17";
        cpp_count += 1;
        cpp_flags_buf[cpp_count] = base_version_flag;
        cpp_count += 1;
        cpp_flags_buf[cpp_count] = base_commit_flag;
        cpp_count += 1;
        cpp_flags_buf[cpp_count] = sched_copies_flag;
        cpp_count += 1;
        for (pf) |f| {
            cpp_flags_buf[cpp_count] = f;
            cpp_count += 1;
        }
        const cpp_flags = cpp_flags_buf[0..cpp_count];

        mod.addCSourceFiles(.{
            .root = ggml.path("src"),
            .files = &.{
                "ggml.cpp",
                "ggml-backend.cpp",
                "ggml-opt.cpp",
                "ggml-threading.cpp",
                "gguf.cpp",
            },
            .flags = cpp_flags,
        });
    }

    {
        var reg_flags_buf: [16][]const u8 = undefined;
        var reg_count: usize = 0;
        reg_flags_buf[reg_count] = "-std=c++17";
        reg_count += 1;
        for (pf) |f| {
            reg_flags_buf[reg_count] = f;
            reg_count += 1;
        }
        if (opt_cpu) {
            reg_flags_buf[reg_count] = "-DGGML_USE_CPU";
            reg_count += 1;
        }
        if (opt_metal) {
            reg_flags_buf[reg_count] = "-DGGML_USE_METAL";
            reg_count += 1;
        }
        const reg_flags = reg_flags_buf[0..reg_count];

        mod.addCSourceFiles(.{
            .root = ggml.path("src"),
            .files = &.{
                "ggml-backend-reg.cpp",
                "ggml-backend-dl.cpp",
            },
            .flags = reg_flags,
        });
    }

    if (opt_cpu) {
        mod.addIncludePath(ggml.path("src/ggml-cpu"));

        const is_x86 = arch == .x86_64 or arch == .x86;
        const is_arm = arch == .aarch64 or arch == .aarch64_be;
        const is_ppc = arch == .powerpc64 or arch == .powerpc64le or arch == .powerpc;
        const is_riscv = arch == .riscv64;
        const is_s390x = arch == .s390x;
        const is_wasm = arch == .wasm32 or arch == .wasm64;
        const is_loongarch = arch == .loongarch64;

        var cpu_c_flags_buf: [48][]const u8 = undefined;
        var cpu_c_count: usize = 0;

        cpu_c_flags_buf[cpu_c_count] = "-std=c11";
        cpu_c_count += 1;
        for (pf) |f| {
            cpu_c_flags_buf[cpu_c_count] = f;
            cpu_c_count += 1;
        }

        var cpu_cpp_flags_buf: [48][]const u8 = undefined;
        var cpu_cpp_count: usize = 0;

        cpu_cpp_flags_buf[cpu_cpp_count] = "-std=c++17";
        cpu_cpp_count += 1;
        for (pf) |f| {
            cpu_cpp_flags_buf[cpu_cpp_count] = f;
            cpu_cpp_count += 1;
        }

        if (opt_cpu_repack) {
            cpu_c_flags_buf[cpu_c_count] = "-DGGML_USE_CPU_REPACK";
            cpu_c_count += 1;
            cpu_cpp_flags_buf[cpu_cpp_count] = "-DGGML_USE_CPU_REPACK";
            cpu_cpp_count += 1;
        }

        if (opt_llamafile) {
            cpu_c_flags_buf[cpu_c_count] = "-DGGML_USE_LLAMAFILE";
            cpu_c_count += 1;
            cpu_cpp_flags_buf[cpu_cpp_count] = "-DGGML_USE_LLAMAFILE";
            cpu_cpp_count += 1;
        }

        if (is_darwin and opt_accelerate) {
            cpu_c_flags_buf[cpu_c_count] = "-DGGML_USE_ACCELERATE";
            cpu_c_count += 1;
            cpu_c_flags_buf[cpu_c_count] = "-DACCELERATE_NEW_LAPACK";
            cpu_c_count += 1;
            cpu_c_flags_buf[cpu_c_count] = "-DACCELERATE_LAPACK_ILP64";
            cpu_c_count += 1;
            cpu_cpp_flags_buf[cpu_cpp_count] = "-DGGML_USE_ACCELERATE";
            cpu_cpp_count += 1;
            cpu_cpp_flags_buf[cpu_cpp_count] = "-DACCELERATE_NEW_LAPACK";
            cpu_cpp_count += 1;
            cpu_cpp_flags_buf[cpu_cpp_count] = "-DACCELERATE_LAPACK_ILP64";
            cpu_cpp_count += 1;
            mod.linkFramework("Accelerate", .{});
        }

        if (is_x86) {
            if (opt_native) {
                cpu_c_flags_buf[cpu_c_count] = "-march=native";
                cpu_c_count += 1;
                cpu_cpp_flags_buf[cpu_cpp_count] = "-march=native";
                cpu_cpp_count += 1;
            } else {
                const isa_flags = .{
                    .{ opt_sse42, "-msse4.2", "-DGGML_SSE42" },
                    .{ opt_avx, "-mavx", "-DGGML_AVX" },
                    .{ opt_avx2, "-mavx2", "-DGGML_AVX2" },
                    .{ opt_fma, "-mfma", "-DGGML_FMA" },
                    .{ opt_f16c, "-mf16c", "-DGGML_F16C" },
                    .{ opt_bmi2, "-mbmi2", "-DGGML_BMI2" },
                    .{ opt_avx_vnni, "-mavxvnni", "-DGGML_AVX_VNNI" },
                    .{ opt_avx512, "-mavx512f", "-DGGML_AVX512" },
                    .{ opt_avx512_vbmi, "-mavx512vbmi", "-DGGML_AVX512_VBMI" },
                    .{ opt_avx512_vnni, "-mavx512vnni", "-DGGML_AVX512_VNNI" },
                    .{ opt_avx512_bf16, "-mavx512bf16", "-DGGML_AVX512_BF16" },
                    .{ opt_amx_tile, "-mamx-tile", "-DGGML_AMX_TILE" },
                    .{ opt_amx_int8, "-mamx-int8", "-DGGML_AMX_INT8" },
                    .{ opt_amx_bf16, "-mamx-bf16", "-DGGML_AMX_BF16" },
                };

                inline for (isa_flags) |entry| {
                    if (entry[0]) {
                        cpu_c_flags_buf[cpu_c_count] = entry[1];
                        cpu_c_count += 1;
                        cpu_c_flags_buf[cpu_c_count] = entry[2];
                        cpu_c_count += 1;
                        cpu_cpp_flags_buf[cpu_cpp_count] = entry[1];
                        cpu_cpp_count += 1;
                        cpu_cpp_flags_buf[cpu_cpp_count] = entry[2];
                        cpu_cpp_count += 1;
                    }
                }

                if (opt_avx512) {
                    const extra_avx512 = [_][]const u8{
                        "-mavx512cd", "-mavx512vl", "-mavx512dq", "-mavx512bw",
                    };
                    for (extra_avx512) |f| {
                        cpu_c_flags_buf[cpu_c_count] = f;
                        cpu_c_count += 1;
                        cpu_cpp_flags_buf[cpu_cpp_count] = f;
                        cpu_cpp_count += 1;
                    }
                }
            }
        } else if (is_arm and opt_native) {
            cpu_c_flags_buf[cpu_c_count] = "-mcpu=native";
            cpu_c_count += 1;
            cpu_cpp_flags_buf[cpu_cpp_count] = "-mcpu=native";
            cpu_cpp_count += 1;
        }

        const cpu_c_flags = cpu_c_flags_buf[0..cpu_c_count];
        const cpu_cpp_flags = cpu_cpp_flags_buf[0..cpu_cpp_count];

        mod.addCSourceFiles(.{
            .root = ggml.path("src"),
            .files = &.{
                "ggml-cpu/ggml-cpu.c",
                "ggml-cpu/quants.c",
            },
            .flags = cpu_c_flags,
        });

        mod.addCSourceFiles(.{
            .root = ggml.path("src"),
            .files = &.{
                "ggml-cpu/ggml-cpu.cpp",
                "ggml-cpu/repack.cpp",
                "ggml-cpu/hbm.cpp",
                "ggml-cpu/traits.cpp",
                "ggml-cpu/amx/amx.cpp",
                "ggml-cpu/amx/mmq.cpp",
                "ggml-cpu/binary-ops.cpp",
                "ggml-cpu/unary-ops.cpp",
                "ggml-cpu/vec.cpp",
                "ggml-cpu/ops.cpp",
            },
            .flags = cpu_cpp_flags,
        });

        if (opt_llamafile) {
            mod.addCSourceFiles(.{
                .root = ggml.path("src"),
                .files = &.{"ggml-cpu/llamafile/sgemm.cpp"},
                .flags = cpu_cpp_flags,
            });
        }

        if (is_x86) {
            mod.addCSourceFiles(.{
                .root = ggml.path("src"),
                .files = &.{"ggml-cpu/arch/x86/quants.c"},
                .flags = cpu_c_flags,
            });
            mod.addCSourceFiles(.{
                .root = ggml.path("src"),
                .files = &.{"ggml-cpu/arch/x86/repack.cpp"},
                .flags = cpu_cpp_flags,
            });
        } else if (is_arm) {
            mod.addCSourceFiles(.{
                .root = ggml.path("src"),
                .files = &.{"ggml-cpu/arch/arm/quants.c"},
                .flags = cpu_c_flags,
            });
            mod.addCSourceFiles(.{
                .root = ggml.path("src"),
                .files = &.{"ggml-cpu/arch/arm/repack.cpp"},
                .flags = cpu_cpp_flags,
            });
        } else if (is_ppc) {
            mod.addCSourceFiles(.{
                .root = ggml.path("src"),
                .files = &.{"ggml-cpu/arch/powerpc/quants.c"},
                .flags = cpu_c_flags,
            });
        } else if (is_riscv) {
            mod.addCSourceFiles(.{
                .root = ggml.path("src"),
                .files = &.{"ggml-cpu/arch/riscv/quants.c"},
                .flags = cpu_c_flags,
            });
            mod.addCSourceFiles(.{
                .root = ggml.path("src"),
                .files = &.{"ggml-cpu/arch/riscv/repack.cpp"},
                .flags = cpu_cpp_flags,
            });
        } else if (is_s390x) {
            mod.addCSourceFiles(.{
                .root = ggml.path("src"),
                .files = &.{"ggml-cpu/arch/s390/quants.c"},
                .flags = cpu_c_flags,
            });
        } else if (is_loongarch) {
            mod.addCSourceFiles(.{
                .root = ggml.path("src"),
                .files = &.{"ggml-cpu/arch/loongarch/quants.c"},
                .flags = cpu_c_flags,
            });
        } else if (is_wasm) {
            mod.addCSourceFiles(.{
                .root = ggml.path("src"),
                .files = &.{"ggml-cpu/arch/wasm/quants.c"},
                .flags = cpu_c_flags,
            });
        }
    }

    if (opt_metal) {
        var metal_cpp_flags_buf: [16][]const u8 = undefined;
        var metal_cpp_count: usize = 0;

        metal_cpp_flags_buf[metal_cpp_count] = "-std=c++17";
        metal_cpp_count += 1;
        for (pf) |f| {
            metal_cpp_flags_buf[metal_cpp_count] = f;
            metal_cpp_count += 1;
        }
        if (opt_metal_embed) {
            metal_cpp_flags_buf[metal_cpp_count] = "-DGGML_METAL_EMBED_LIBRARY";
            metal_cpp_count += 1;
        }

        const metal_cpp_flags = metal_cpp_flags_buf[0..metal_cpp_count];

        mod.addCSourceFiles(.{
            .root = ggml.path("src/ggml-metal"),
            .files = &.{
                "ggml-metal.cpp",
                "ggml-metal-device.cpp",
                "ggml-metal-common.cpp",
                "ggml-metal-ops.cpp",
            },
            .flags = metal_cpp_flags,
        });

        var metal_objc_flags_buf: [16][]const u8 = undefined;
        var metal_objc_count: usize = 0;
        for (pf) |f| {
            metal_objc_flags_buf[metal_objc_count] = f;
            metal_objc_count += 1;
        }
        if (opt_metal_embed) {
            metal_objc_flags_buf[metal_objc_count] = "-DGGML_METAL_EMBED_LIBRARY";
            metal_objc_count += 1;
        }

        const metal_objc_flags = metal_objc_flags_buf[0..metal_objc_count];

        mod.addCSourceFiles(.{
            .root = ggml.path("src/ggml-metal"),
            .files = &.{
                "ggml-metal-device.m",
                "ggml-metal-context.m",
            },
            .flags = metal_objc_flags,
        });

        mod.linkFramework("Foundation", .{});
        mod.linkFramework("Metal", .{});
        mod.linkFramework("MetalKit", .{});

        if (opt_metal_embed) {
            const embed_tool = b.addExecutable(.{
                .name = "embed-metal",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("build/embed_metal.zig"),
                    .target = b.graph.host,
                }),
            });

            const embed_run = b.addRunArtifact(embed_tool);
            embed_run.addFileArg(ggml.path("src/ggml-metal/ggml-metal.metal"));
            embed_run.addFileArg(ggml.path("src/ggml-common.h"));
            embed_run.addFileArg(ggml.path("src/ggml-metal/ggml-metal-impl.h"));
            const embed_asm = embed_run.addOutputFileArg("ggml-metal-embed.s");

            mod.addAssemblyFile(embed_asm);
        }
    }

    if (is_linux) {
        mod.linkSystemLibrary("dl", .{});
    }

    lib.installHeadersDirectory(ggml.path("include"), "", .{});
    b.installArtifact(lib);

    const test_exe = b.addExecutable(.{
        .name = "test-ggml",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    test_exe.root_module.addCSourceFile(.{
        .file = b.path("test/basic.c"),
    });
    test_exe.root_module.linkLibrary(lib);

    const run_test = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run basic tests");
    test_step.dependOn(&run_test.step);
}
