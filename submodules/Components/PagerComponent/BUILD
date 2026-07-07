load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "PagerComponent",
    module_name = "PagerComponent",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
    ],
    deps = [
        "//submodules/Display:Display",
        "//submodules/ComponentFlow:ComponentFlow",
        "//submodules/DirectionalPanGesture:DirectionalPanGesture",
    ],
    visibility = [
        "//visibility:public",
    ],
)
