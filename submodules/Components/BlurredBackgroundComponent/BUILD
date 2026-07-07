load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "BlurredBackgroundComponent",
    module_name = "BlurredBackgroundComponent",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
    ],
    deps = [
        "//submodules/Display:Display",
        "//submodules/ComponentFlow:ComponentFlow",
        "//submodules/Components/ComponentDisplayAdapters:ComponentDisplayAdapters",
    ],
    visibility = [
        "//visibility:public",
    ],
)
