load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

load(
    "@build_bazel_rules_apple//apple:resources.bzl",
    "apple_resource_bundle",
    "apple_resource_group",
)
load("//build-system/bazel-utils:plist_fragment.bzl",
    "plist_fragment",
)

filegroup(
    name = "LiquidGlassMetalSources",
    srcs = glob([
        "MetalResources/**/*.metal",
    ]),
    visibility = ["//visibility:public"],
)

plist_fragment(
    name = "LiquidGlassMetalSourcesBundleInfoPlist",
    extension = "plist",
    template =
    """
    <key>CFBundleIdentifier</key>
    <string>org.telegram.LiquidGlassMetalSources</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleName</key>
    <string>LiquidGlassEffect</string>
    """
)

apple_resource_bundle(
    name = "LiquidGlassMetalSourcesBundle",
    infoplists = [
        ":LiquidGlassMetalSourcesBundleInfoPlist",
    ],
    resources = [
        ":LiquidGlassMetalSources",
    ],
)

swift_library(
    name = "LiquidGlassEffect",
    module_name = "LiquidGlassEffect",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    data = [
        ":LiquidGlassMetalSourcesBundle",
    ],
    deps = [
        "//submodules/Display",
        "//submodules/MetalEngine",
        "//submodules/LegacyComponents",
    ],
    visibility = [
        "//visibility:public",
    ],
)
