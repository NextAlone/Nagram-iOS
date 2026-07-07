load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SubcodecMultiAnimationRendererImpl",
    module_name = "SubcodecMultiAnimationRendererImpl",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Display:Display",
        "//submodules/TelegramUI/Components/AnimationCache:AnimationCache",
        "//submodules/TelegramUI/Components/MultiAnimationRenderer:MultiAnimationRenderer",
        "//submodules/TelegramUI/Components/SubcodecAnimationCacheImpl:SubcodecAnimationCacheImpl",
        "//third-party/subcodec:SubcodecObjC",
    ],
    visibility = [
        "//visibility:public",
    ],
)
