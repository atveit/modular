"""Target-configured, sandboxed Mojo and CompilerRT iOS archives."""

load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain", "use_cpp_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

MojoIOSArchiveInfo = provider(
    doc = "A target-configured Mojo iOS archive and its C ABI header.",
    fields = {
        "archive": "The generated static archive.",
        "header": "The exported C ABI header.",
        "target_triple": "The Mojo target triple used for object emission.",
    },
)

CompilerRTIOSCoreInfo = provider(
    doc = "The bounded non-AsyncRT iOS core archive.",
    fields = {
        "archive": "The generated static archive.",
    },
)

def _feature_configuration(ctx, cc_toolchain):
    return cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

def _archive_compilation_outputs(ctx, cc_toolchain, feature_configuration, name, compilation_outputs):
    linking_context, linking_outputs = cc_common.create_linking_context_from_compilation_outputs(
        actions = ctx.actions,
        cc_toolchain = cc_toolchain,
        compilation_outputs = compilation_outputs,
        disallow_dynamic_library = True,
        feature_configuration = feature_configuration,
        name = name,
    )
    library = linking_outputs.library_to_link
    archive = library.static_library or library.pic_static_library
    if not archive:
        fail("iOS archive action did not produce a static library")
    return archive, linking_context

def _mojo_ios_archive_impl(ctx):
    cc_toolchain = find_cpp_toolchain(ctx)
    feature_configuration = _feature_configuration(ctx, cc_toolchain)
    mojo_toolchain = ctx.toolchains["@rules_mojo//:toolchain_type"].mojo_toolchain_info

    object_file = ctx.actions.declare_file(ctx.label.name + ".o")
    header = ctx.actions.declare_file(ctx.label.name + ".h")
    c_compiler = ctx.actions.declare_file(ctx.label.name + ".toolchain/clang")
    cpp_compiler = ctx.actions.declare_file(ctx.label.name + ".toolchain/clang++")
    ctx.actions.symlink(
        is_executable = True,
        output = c_compiler,
        target_file = ctx.executable._c_compiler,
    )
    ctx.actions.symlink(
        is_executable = True,
        output = cpp_compiler,
        target_file = ctx.executable._cpp_compiler,
    )
    args = ctx.actions.args()
    args.add("build")
    args.add("-I", "mojo/stdlib")
    args.add("--target-triple", ctx.attr.target_triple)
    args.add("--target-cpu", ctx.attr.target_cpu)
    args.add("--emit", "object")
    args.add(ctx.file.src)
    args.add("-o", object_file)

    action_env = dict(getattr(ctx.toolchains["@rules_mojo//:toolchain_type"], "build_env", {}))
    action_env.update({
        "CC": "clang",
        "CXX": "clang++",
        "MODULAR_HOME": ".",
        "MODULAR_MOJO_MAX_LLD_PATH": "/dev/null",
        "MOJO_CRASHPAD": "0",
        "PATH": c_compiler.dirname + ":/usr/bin:/bin:/usr/sbin:/sbin",
        "ZERO_AR_DATE": "1",
    })
    ctx.actions.run(
        arguments = [args],
        env = action_env,
        executable = mojo_toolchain.mojo,
        execution_requirements = {"supports-path-mapping": "1"},
        inputs = depset(
            direct = [ctx.file.src],
            transitive = [depset(ctx.files._stdlib)],
        ),
        mnemonic = "MojoIOSCompile",
        outputs = [object_file],
        progress_message = "Compiling target-configured Mojo iOS object %{label}",
        toolchain = "@rules_mojo//:toolchain_type",
        tools = mojo_toolchain.all_tools + [cc_toolchain.all_files, c_compiler, cpp_compiler],
    )
    ctx.actions.symlink(output = header, target_file = ctx.file.header)

    compilation_outputs = cc_common.create_compilation_outputs(
        objects = depset([object_file]),
    )
    archive, linking_context = _archive_compilation_outputs(
        ctx,
        cc_toolchain,
        feature_configuration,
        ctx.label.name,
        compilation_outputs,
    )
    compilation_context = cc_common.create_compilation_context(
        headers = depset([header]),
        includes = depset([header.dirname]),
    )
    return [
        DefaultInfo(files = depset([archive, header])),
        CcInfo(
            compilation_context = compilation_context,
            linking_context = linking_context,
        ),
        MojoIOSArchiveInfo(
            archive = archive,
            header = header,
            target_triple = ctx.attr.target_triple,
        ),
    ]

mojo_ios_archive = rule(
    implementation = _mojo_ios_archive_impl,
    attrs = {
        "header": attr.label(allow_single_file = [".h"], mandatory = True),
        "src": attr.label(allow_single_file = [".mojo"], mandatory = True),
        "target_cpu": attr.string(mandatory = True),
        "target_triple": attr.string(mandatory = True),
        "_c_compiler": attr.label(
            cfg = "exec",
            default = Label("//bazel/internal/cc-toolchain/tools:multi-platform-clang"),
            executable = True,
        ),
        "_cpp_compiler": attr.label(
            cfg = "exec",
            default = Label("//bazel/internal/cc-toolchain/tools:multi-platform-clang++"),
            executable = True,
        ),
        "_stdlib": attr.label(
            allow_files = [".mojo"],
            default = Label("//mojo/stdlib/std:std_srcs"),
        ),
    },
    doc = "Builds a runtime-free Mojo archive with registered target toolchains.",
    fragments = ["cpp"],
    toolchains = use_cpp_toolchain() + ["@rules_mojo//:toolchain_type"],
)

def _compilerrt_ios_core_impl(ctx):
    cc_toolchain = find_cpp_toolchain(ctx)
    feature_configuration = _feature_configuration(ctx, cc_toolchain)
    dependency_contexts = [dep[CcInfo].compilation_context for dep in ctx.attr._compilation_deps]
    compilation_context, compilation_outputs = cc_common.compile(
        actions = ctx.actions,
        cc_toolchain = cc_toolchain,
        compilation_contexts = dependency_contexts,
        feature_configuration = feature_configuration,
        local_defines = ["MODULAR_BUILDING_COMPILERRT"],
        name = ctx.label.name,
        srcs = ctx.files.srcs,
    )
    archive, linking_context = _archive_compilation_outputs(
        ctx,
        cc_toolchain,
        feature_configuration,
        ctx.label.name,
        compilation_outputs,
    )
    return [
        DefaultInfo(files = depset([archive])),
        CcInfo(
            compilation_context = compilation_context,
            linking_context = linking_context,
        ),
        CompilerRTIOSCoreInfo(archive = archive),
    ]

compilerrt_ios_core = rule(
    implementation = _compilerrt_ios_core_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = [".cpp"], mandatory = True),
        "_compilation_deps": attr.label_list(
            default = [
                Label("//Support:SymbolExport"),
            ],
            providers = [CcInfo],
        ),
    },
    doc = "Builds the bounded non-AsyncRT core with the registered C++ toolchain.",
    fragments = ["cpp"],
    toolchains = use_cpp_toolchain(),
)
