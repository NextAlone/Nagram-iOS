load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ChatInputPanelContainer",
    module_name = "ChatInputPanelContainer",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/Components/PagerComponent:PagerComponent",
    ],
    visibility = [
        "//visibility:public",
    ],
)
