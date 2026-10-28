load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: NAGRAM — Telegram 原生 SharedData 设置的 iCloud KVS 同步桥。
swift_library(
    name = "NagramTelegramSettingsCloudSync",
    module_name = "NagramTelegramSettingsCloudSync",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Nagram/Settings:NagramSettings",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
    ],
    visibility = [
        "//visibility:public",
    ],
)
