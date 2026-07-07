load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: NAGRAM — 媒体查看器 "查看信息" 功能。
# 收集图片/视频的分辨率、时长、帧率、码率、编码等 metadata 并弹窗展示。
swift_library(
    name = "NagramMediaMetadata",
    module_name = "NagramMediaMetadata",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Display:Display",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/AlertUI:AlertUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)
