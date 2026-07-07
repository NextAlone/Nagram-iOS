load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "CounterControllerTitleView",
    module_name = "CounterControllerTitleView",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
    ],
    deps = [
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/ComponentFlow",
    ],
    visibility = [
        "//visibility:public",
    ],
)
