load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ManagedFile",
    module_name = "ManagedFile",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)
