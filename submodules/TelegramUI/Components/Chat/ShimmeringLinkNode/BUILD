load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ShimmeringLinkNode",
    module_name = "ShimmeringLinkNode",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
    ],
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/ShimmerEffect",
    ],
    visibility = [
        "//visibility:public",
    ],
)
