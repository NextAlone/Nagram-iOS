load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ActivityIndicatorComponent",
    module_name = "ActivityIndicatorComponent",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
    ],
    deps = [
        "//submodules/ComponentFlow:ComponentFlow",
    ],
    visibility = [
        "//visibility:public",
    ],
)
