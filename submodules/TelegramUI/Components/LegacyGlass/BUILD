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
    name = "LegacyGlassMetalResources",
    srcs = glob([
        "MetalResources/**/*.metal",
    ]),
    visibility = ["//visibility:public"],
)

plist_fragment(
    name = "LegacyGlassMetalResourcesBundleInfoPlist",
    extension = "plist",
    template =
    """
    <key>CFBundleIdentifier</key>
    <string>org.telegram.LegacyGlassMetalResources</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleName</key>
    <string>LegacyGlass</string>
    """
)

apple_resource_bundle(
    name = "LegacyGlassMetalResourcesBundle",
    infoplists = [
        ":LegacyGlassMetalResourcesBundleInfoPlist",
    ],
    resources = [
        ":LegacyGlassMetalResources",
    ],
)

swift_library(
    name = "LegacyGlass",
    module_name = "LegacyGlass",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    data = [
        ":LegacyGlassMetalResourcesBundle",
    ],
    deps = [
        "//submodules/Display",
        "//submodules/ComponentFlow",
        "//submodules/UIKitRuntimeUtils",
    ],
    visibility = [
        "//visibility:public",
    ],
)