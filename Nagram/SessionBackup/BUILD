load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: NAGRAM — 会话备份数据层（Pyrogram 会话串编解码 + 备份信封 + Keychain 存储）。
# 零 Telegram 依赖，便于独立测试；与 iebb/mithka 双向兼容的格式定义都在这里。
swift_library(
    name = "NagramSessionBackup",
    module_name = "NagramSessionBackup",
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
