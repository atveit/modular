"""Diagnostic Bazel action for a runtime-free Mojo iOS static library."""

MojoIOSStaticLibraryInfo = provider(
    doc = "C-linkable Mojo iOS archive and its exported C header.",
    fields = {
        "archive": "The generated static archive.",
        "header": "The exported C ABI header.",
        "target_triple": "The Mojo target triple used for the archive.",
    },
)

def _mojo_ios_static_library_impl(ctx):
    object_file = ctx.actions.declare_file(ctx.label.name + ".o")
    archive = ctx.actions.declare_file("lib" + ctx.label.name + ".a")
    header = ctx.actions.declare_file(ctx.label.name + ".h")
    mojo_toolchain = ctx.toolchains["@rules_mojo//:toolchain_type"].mojo_toolchain_info
    mojo = mojo_toolchain.mojo

    command = """
set -euo pipefail
sdk_name=iphonesimulator
sdk_path="$(/usr/bin/xcrun --sdk "${{sdk_name}}" --show-sdk-path)"
libtool_bin="$(/usr/bin/xcrun --sdk "${{sdk_name}}" --find libtool)"
ar_bin="$(/usr/bin/xcrun --sdk "${{sdk_name}}" --find ar)"
vtool_bin="$(/usr/bin/xcrun --find vtool)"

"{mojo}" build --target-triple "{triple}" --target-cpu apple-m1 --emit object "{src}" -o "{object_file}"
"${{libtool_bin}}" -static -o "{archive}" "{object_file}"
cp "{abi_header}" "{header}"

member="$("${{ar_bin}}" -t "{archive}")"
test "${{member}}" = "$(basename "{object_file}")"
extract_dir="$(mktemp -d "${{TMPDIR:-/tmp}}/mojo-ios-static-library.XXXXXX")"
trap 'rm -rf "${{extract_dir}}"' EXIT
(
  cd "${{extract_dir}}"
  "${{ar_bin}}" -x "{archive}"
)
"${{vtool_bin}}" -show-build "${{extract_dir}}/${{member}}" | grep -q 'platform IOSSIMULATOR'
nm -gU "${{object_file}}" | grep -Eq '(_?mojo_add)$'
nm -gU "${{object_file}}" | grep -Eq '(_?mojo_hello_utf8)$'
""".format(
        abi_header = ctx.file.header.path,
        archive = archive.path,
        header = header.path,
        mojo = mojo.path,
        object_file = object_file.path,
        src = ctx.file.src.path,
        triple = ctx.attr.target_triple,
    )

    ctx.actions.run_shell(
        inputs = [ctx.file.src, ctx.file.header],
        outputs = [object_file, archive, header],
        tools = mojo_toolchain.all_tools,
        command = command,
        env = getattr(ctx.toolchains["@rules_mojo//:toolchain_type"], "build_env", {}),
        mnemonic = "MojoIOSStaticLibrary",
        progress_message = "Building runtime-free Mojo iOS static library %{label}",
    )
    return [
        DefaultInfo(files = depset([archive, header])),
        MojoIOSStaticLibraryInfo(
            archive = archive,
            header = header,
            target_triple = ctx.attr.target_triple,
        ),
    ]

mojo_ios_static_library = rule(
    implementation = _mojo_ios_static_library_impl,
    attrs = {
        "src": attr.label(allow_single_file = [".mojo"], mandatory = True),
        "header": attr.label(allow_single_file = [".h"], mandatory = True),
        "target_triple": attr.string(default = "arm64-apple-ios17.0-simulator"),
    },
    toolchains = ["@rules_mojo//:toolchain_type"],
    doc = "Builds only the runtime-free C ABI fixture as an iOS Simulator archive.",
)
