"""A narrow, local Xcode action for the iOS Simulator CompilerRT seed."""

def _compilerrt_ios_bootstrap_archive_impl(ctx):
    object_files = [
        ctx.actions.declare_file(ctx.label.name + "/" + source.basename[:-4] + ".o")
        for source in ctx.files.srcs
    ]
    archive = ctx.actions.declare_file("lib" + ctx.label.name + ".a")
    source_paths = " ".join([source.path for source in ctx.files.srcs])
    object_paths = " ".join([obj.path for obj in object_files])
    checks = "\n".join([
        "nm -gU \"{archive}\" | grep -qx \".*{symbol}\"".format(
            archive = archive.path,
            symbol = symbol,
        )
        for symbol in [
            "_KGEN_CompilerRT_AlignedAlloc",
            "_KGEN_CompilerRT_AlignedFree",
            "_KGEN_CompilerRT_Initialize",
            "_KGEN_CompilerRT_GetOrCreateGlobal",
            "_KGEN_CompilerRT_DestroyGlobals",
            "___truncsfbf2",
        ]
    ])

    command = """
set -euo pipefail
sdk_path="$(/usr/bin/xcrun --sdk iphonesimulator --show-sdk-path)"
clangxx_bin="$(/usr/bin/xcrun --sdk iphonesimulator --find clang++)"
libtool_bin="$(/usr/bin/xcrun --sdk iphonesimulator --find libtool)"
vtool_bin="$(/usr/bin/xcrun --find vtool)"
llvm_source_include="$PWD/external/+llvm_configure+llvm-project/llvm/include"
llvm_generated_include="{bin_dir}/external/+llvm_configure+llvm-project/llvm/include"
test -d "${{llvm_source_include}}"
test -d "${{llvm_generated_include}}"

sources=({sources})
objects=({objects})
for index in "${{!sources[@]}}"; do
  "${{clangxx_bin}}" -target arm64-apple-ios17.0-simulator \
    -isysroot "${{sdk_path}}" -mios-simulator-version-min=17.0 -arch arm64 \
    -std=c++20 -DMODULAR_BUILDING_COMPILERRT -ISupport/include \
    -isystem "${{llvm_source_include}}" -isystem "${{llvm_generated_include}}" \
    -c "${{sources[$index]}}" -o "${{objects[$index]}}"
  "${{vtool_bin}}" -show-build "${{objects[$index]}}" | grep -q 'platform IOSSIMULATOR'
done
"${{libtool_bin}}" -static -o "{archive}" "${{objects[@]}}"
{checks}
""".format(
        archive = archive.path,
        bin_dir = ctx.bin_dir.path,
        checks = checks,
        objects = object_paths,
        sources = source_paths,
    )

    # This is intentionally local and non-sandboxed: no iOS C++ toolchain or
    # iPhoneSimulator SDK repository is registered. The seed materializes
    # generated LLVM headers; its host archive is never read by this action.
    ctx.actions.run_shell(
        inputs = ctx.files.srcs + [ctx.file._llvm_header_seed],
        outputs = object_files + [archive],
        command = command,
        mnemonic = "CompilerRTIOSSimulatorBootstrap",
        progress_message = "SDK-compiling CompilerRT iOS Simulator seed %{label}",
        execution_requirements = {
            "local": "1",
            "no-sandbox": "1",
        },
    )
    return [DefaultInfo(files = depset([archive]))]

compilerrt_ios_simulator_bootstrap_archive = rule(
    implementation = _compilerrt_ios_bootstrap_archive_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = [".cpp"], mandatory = True),
        "_llvm_header_seed": attr.label(
            default = Label("//KGEN:CompilerRTIOSStatic"),
            allow_single_file = True,
        ),
    },
    doc = "Builds the four-source SDK-native CompilerRT Simulator seed only.",
)
