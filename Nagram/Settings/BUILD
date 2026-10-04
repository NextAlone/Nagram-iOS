load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: NAGRAM — Nagram 增强开关模块（轻量 UserDefaults 单例 + iCloud KVS 镜像，零 Telegram 依赖）。
# 独立顶层模块，不混入上游 Preferences；rebase 时上游碰不到 Nagram/。
swift_library(
    name = "NagramSettings",
    module_name = "NagramSettings",
    srcs = glob([
        "**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    visibility = [
        "//visibility:public",
    ],
)

filegroup(
    name = "RegistrationDateTable",
    srcs = ["Resources/NagramIdDate.json"],
    visibility = ["//visibility:public"],
)
