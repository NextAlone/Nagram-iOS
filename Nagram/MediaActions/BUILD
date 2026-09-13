load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "NagramMediaActions",
    module_name = "NagramMediaActions",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        "//Nagram/Strings:NagramStrings",
        "//submodules/AccountContext",
        "//submodules/Display",
        "//submodules/OverlayStatusController",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/SaveToCameraRoll",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/UndoUI",
    ],
    visibility = ["//visibility:public"],
)
