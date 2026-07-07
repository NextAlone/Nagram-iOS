load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "BackButtonComponent",
    module_name = "BackButtonComponent",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
    ],
    deps = [
        "//submodules/ComponentFlow",
        "//submodules/Components/MultilineTextComponent",
        "//submodules/Display",
    ],
    visibility = [
        "//visibility:public",
    ],
)
