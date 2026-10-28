load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: NAGRAM — Unified translation service providers.
swift_library(
    name = "NagramTranslate",
    module_name = "NagramTranslate",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Nagram/Settings:NagramSettings",
        "//submodules/AccountContext:AccountContext",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramCore:TelegramCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
