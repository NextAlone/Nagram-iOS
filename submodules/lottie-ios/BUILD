load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "Lottie",
    module_name = "Lottie",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
    ],
    deps = [
        "//submodules/Display"
    ],
    visibility = [
        "//visibility:public",
    ],
)
