load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "BundleIconComponent",
    module_name = "BundleIconComponent",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
    ],
    deps = [
        "//submodules/ComponentFlow:ComponentFlow",
        "//submodules/AppBundle:AppBundle",
        "//submodules/Display:Display",
    ],
    visibility = [
        "//visibility:public",
    ],
)
