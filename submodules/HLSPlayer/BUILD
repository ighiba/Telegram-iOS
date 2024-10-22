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
    name = "HLSPlayerMetalResources",
    srcs = glob([
        "MetalResources/**/*.metal",
    ]),
    visibility = ["//visibility:public"],
)

plist_fragment(
    name = "HLSPlayerBundleInfoPlist",
    extension = "plist",
    template =
    """
    <key>CFBundleIdentifier</key>
    <string>org.telegram.HLSPlayer</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleName</key>
    <string>HLSPlayer</string>
    """
)

apple_resource_bundle(
    name = "HLSPlayerBundle",
    infoplists = [
        ":HLSPlayerBundleInfoPlist",
    ],
    resources = [
        ":HLSPlayerMetalResources",
    ],
)

swift_library(
    name = "HLSPlayer",
    module_name = "HLSPlayer",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    data = [
        ":HLSPlayerBundle",
    ],
    deps = [
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/TelegramAudio:TelegramAudio",
        "//submodules/FFMpegBinding:FFMpegBinding",
        "//submodules/RingBuffer:RingBuffer",
        "//submodules/YuvConversion:YuvConversion",
    ],
    visibility = [
        "//visibility:public",
    ],
)
