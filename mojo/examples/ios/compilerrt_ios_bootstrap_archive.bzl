"""Narrow local Xcode actions for target-correct iOS CompilerRT seeds."""

def _compilerrt_ios_static_archive_impl(ctx):
    object_files = [
        ctx.actions.declare_file(ctx.label.name + "/" + source.basename[:-4] + ".o")
        for source in ctx.files.srcs
    ]
    archive = ctx.actions.declare_file("lib" + ctx.label.name + ".a")
    source_paths = " ".join([source.path for source in ctx.files.srcs])
    object_paths = " ".join([obj.path for obj in object_files])
    checks = "\n".join([
        "grep -q \"{symbol}$\" \"${{symbol_manifest}}\"".format(
            symbol = symbol,
        )
        for symbol in ctx.attr.expected_symbols
    ])
    forbidden_checks = "\n".join([
        "if grep -Eq '{pattern}' \"${{symbol_manifest}}\"; then echo \"forbidden CompilerRT symbol family: {pattern}\" >&2; exit 1; fi".format(
            pattern = pattern,
        )
        for pattern in ctx.attr.forbidden_symbol_patterns
    ])

    command = """
set -euo pipefail
sdk_path="$(/usr/bin/xcrun --sdk {sdk_name} --show-sdk-path)"
clangxx_bin="$(/usr/bin/xcrun --sdk {sdk_name} --find clang++)"
libtool_bin="$(/usr/bin/xcrun --sdk {sdk_name} --find libtool)"
vtool_bin="$(/usr/bin/xcrun --find vtool)"
llvm_source_include="$PWD/external/+llvm_configure+llvm-project/llvm/include"
llvm_generated_include="{bin_dir}/external/+llvm_configure+llvm-project/llvm/include"
test -d "${{llvm_source_include}}"
test -d "${{llvm_generated_include}}"

sources=({sources})
objects=({objects})
for index in "${{!sources[@]}}"; do
  "${{clangxx_bin}}" -target {target_triple} \
    -isysroot "${{sdk_path}}" {minimum_os_flag} -arch arm64 \
    -std=c++20 -DMODULAR_BUILDING_COMPILERRT -ISupport/include \
    -isystem "${{llvm_source_include}}" -isystem "${{llvm_generated_include}}" \
    -c "${{sources[$index]}}" -o "${{objects[$index]}}"
  "${{vtool_bin}}" -show-build "${{objects[$index]}}" | grep -q 'platform {expected_platform}'
done
"${{libtool_bin}}" -static -o "{archive}" "${{objects[@]}}"
symbol_manifest="$(mktemp)"
nm -gU "{archive}" > "${{symbol_manifest}}"
{checks}
{forbidden_checks}
""".format(
        archive = archive.path,
        bin_dir = ctx.bin_dir.path,
        checks = checks,
        expected_platform = ctx.attr.expected_platform,
        forbidden_checks = forbidden_checks,
        minimum_os_flag = ctx.attr.minimum_os_flag,
        objects = object_paths,
        sdk_name = ctx.attr.sdk_name,
        sources = source_paths,
        target_triple = ctx.attr.target_triple,
    )

    # This is intentionally local and non-sandboxed: no iOS C++ toolchain or
    # iPhoneSimulator SDK repository is registered. The seed materializes
    # generated LLVM headers; its host archive is never read by this action.
    ctx.actions.run_shell(
        inputs = ctx.files.srcs + [ctx.file._llvm_header_seed],
        outputs = object_files + [archive],
        command = command,
        mnemonic = "CompilerRTIOSCoreArchive",
        progress_message = "SDK-compiling target-correct CompilerRT iOS core %{label}",
        execution_requirements = {
            "local": "1",
            "no-sandbox": "1",
        },
    )
    return [DefaultInfo(files = depset([archive]))]

_compilerrt_ios_static_archive = rule(
    implementation = _compilerrt_ios_static_archive_impl,
    attrs = {
        "expected_platform": attr.string(mandatory = True),
        "expected_symbols": attr.string_list(mandatory = True),
        "forbidden_symbol_patterns": attr.string_list(),
        "minimum_os_flag": attr.string(mandatory = True),
        "sdk_name": attr.string(mandatory = True),
        "srcs": attr.label_list(allow_files = [".cpp"], mandatory = True),
        "target_triple": attr.string(mandatory = True),
        "_llvm_header_seed": attr.label(
            default = Label("//KGEN:CompilerRTIOSBootstrapHost"),
            allow_single_file = True,
        ),
    },
    doc = "Builds an explicit SDK-native CompilerRT iOS seed archive.",
)

def compilerrt_ios_static_archive(
        name,
        srcs,
        expected_symbols,
        forbidden_symbol_patterns = [
            "KGEN_CompilerRT_AsyncRT_",
            "KGEN_CompilerRT_.*Python",
            "KGEN_CompilerRT_.*JIT",
            "KGEN_CompilerRT_.*Tracy",
            "TCMalloc",
        ],
        platform = "IOSSIMULATOR",
        sdk_name = "iphonesimulator",
        target_triple = "arm64-apple-ios17.0-simulator",
        minimum_os_flag = "-mios-simulator-version-min=17.0",
        **kwargs):
    """Creates one target-correct iOS archive using the selected Xcode SDK."""
    _compilerrt_ios_static_archive(
        name = name,
        expected_platform = platform,
        expected_symbols = expected_symbols,
        forbidden_symbol_patterns = forbidden_symbol_patterns,
        minimum_os_flag = minimum_os_flag,
        sdk_name = sdk_name,
        srcs = srcs,
        target_triple = target_triple,
        **kwargs
    )

def compilerrt_ios_simulator_bootstrap_archive(name, srcs, **kwargs):
    """Compatibility wrapper for the original four-source Simulator probe."""
    compilerrt_ios_static_archive(
        name = name,
        srcs = srcs,
        expected_symbols = [
            "_KGEN_CompilerRT_AlignedAlloc",
            "_KGEN_CompilerRT_AlignedFree",
            "_KGEN_CompilerRT_Initialize",
            "_KGEN_CompilerRT_GetOrCreateGlobal",
            "_KGEN_CompilerRT_DestroyGlobals",
            "___truncsfbf2",
        ],
        **kwargs
    )
