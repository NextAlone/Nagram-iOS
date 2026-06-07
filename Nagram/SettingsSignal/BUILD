load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: NAGRAM — 增强开关响应式桥接（UserDefaults → Signal），供需即时刷新的功能（hideStories 等）订阅。
swift_library(
    name = "NagramSettingsSignal",
    module_name = "NagramSettingsSignal",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)
