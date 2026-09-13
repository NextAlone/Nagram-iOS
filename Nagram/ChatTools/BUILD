load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "NagramChatTools",
    module_name = "NagramChatTools",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        "//Nagram/Strings:NagramStrings",
        "//submodules/ComponentFlow",
        "//submodules/TelegramPresentationData",
    ],
    visibility = ["//visibility:public"],
)
