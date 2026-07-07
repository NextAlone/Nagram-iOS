load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ChatMessageTransitionNode",
    module_name = "ChatMessageTransitionNode",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
    ],
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/AccountContext",
    ],
    visibility = [
        "//visibility:public",
    ],
)
