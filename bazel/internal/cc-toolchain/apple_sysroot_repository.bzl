"""Create a local repository from an Xcode Apple-platform SDK."""

def _apple_sysroot_repository_impl(rctx):
    if rctx.os.name != "mac os x":
        rctx.file("sysroot/BUILD.bazel", """\
load("@bazel_skylib//rules/directory:directory.bzl", "directory")

directory(name = "root", srcs = [], visibility = ["//visibility:public"])
filegroup(name = "directory", srcs = [], visibility = ["//visibility:public"])
""")
        return

    developer_dir = rctx.getenv("DEVELOPER_DIR")
    result = rctx.execute(
        ["/usr/bin/xcrun", "--show-sdk-path", "--sdk", rctx.attr.sdk_name],
        environment = {"DEVELOPER_DIR": developer_dir},
    )
    if result.return_code != 0:
        fail("Failed locating {} SDK: {}".format(rctx.attr.sdk_name, result.stderr))

    sdk_path = rctx.path(result.stdout.strip())
    for child in sdk_path.readdir(watch = "no"):
        rctx.symlink(child, "sysroot/" + child.basename)

    framework_includes = [
        "System/Library/Frameworks/{}.framework/**".format(name)
        for name in rctx.attr.frameworks
    ]
    rctx.file("sysroot/BUILD.bazel", """\
load("@bazel_skylib//rules/directory:directory.bzl", "directory")

_INCLUDES = {includes}

directory(name = "root", srcs = glob(_INCLUDES), visibility = ["//visibility:public"])
filegroup(name = "directory", srcs = glob(_INCLUDES), visibility = ["//visibility:public"])
""".format(includes = repr([
        "usr/lib/**",
        "usr/include/**",
    ] + framework_includes)))

apple_sysroot_repository = repository_rule(
    implementation = _apple_sysroot_repository_impl,
    attrs = {
        "frameworks": attr.string_list(),
        "sdk_name": attr.string(mandatory = True),
    },
    environ = ["XCODE_VERSION", "DEVELOPER_DIR"],
    local = True,
    configure = True,
)
