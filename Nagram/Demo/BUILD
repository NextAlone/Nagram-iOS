load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "NagramDemo",
    module_name = "NagramDemo",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        "//submodules/Postbox",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/TelegramUIPreferences",
    ],
    visibility = ["//submodules/TelegramUI:__pkg__"],
)
