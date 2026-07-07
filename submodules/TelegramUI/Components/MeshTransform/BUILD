load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "MeshTransform",
    module_name = "MeshTransform",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
    ],
    deps = [
        "//submodules/TelegramUI/Components/MeshTransform/MeshTransformApi"
    ],
    visibility = [
        "//visibility:public",
    ],
)
