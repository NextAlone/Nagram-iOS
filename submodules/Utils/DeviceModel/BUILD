load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "DeviceModel",
    module_name = "DeviceModel",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/LegacyComponents",
        "//submodules/AccountContext",
    ],
    visibility = [
        "//visibility:public",
    ],
)
