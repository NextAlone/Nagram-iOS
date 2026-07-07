load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ChatMessageItemCommon",
    module_name = "ChatMessageItemCommon",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
    ],
    deps = [
        "//submodules/Display",
        "//submodules/TelegramCore",
        "//submodules/Emoji",
    ],
    visibility = [
        "//visibility:public",
    ],
)

