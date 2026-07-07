load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "PollBubbleTimerNode",
    module_name = "PollBubbleTimerNode",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
    ],
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
    ],
    visibility = [
        "//visibility:public",
    ],
)
