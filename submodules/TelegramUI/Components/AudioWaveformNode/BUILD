load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "AudioWaveformNode",
    module_name = "AudioWaveformNode",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
    ],
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/AudioWaveform",
    ],
    visibility = [
        "//visibility:public",
    ],
)
