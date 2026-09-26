load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "NagramTranscription",
    module_name = "NagramTranscription",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        "//Nagram/Settings:NagramSettings",
        "//Nagram/Strings:NagramStrings",
        "//submodules/AccountContext:AccountContext",
        "//submodules/AppBundle:AppBundle",
        "//submodules/Media/LocalAudioTranscription:LocalAudioTranscription",
        "//submodules/MediaPlayer:UniversalMediaPlayer",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramCore:TelegramCore",
    ],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "TestAudio",
    srcs = ["Resources/NagramSTTTest.m4a"],
    visibility = ["//visibility:public"],
)
