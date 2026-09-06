load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: NAGRAM — 会话备份 UI 层与账号桥接。
# 单独成模块（不放进 Nagram/SettingsUI）是因为登录页也要用：
# AuthorizationUI 依赖本模块提供首次启动导入入口，避免把整个设置页拖进登录流程。
swift_library(
    name = "NagramSessionBackupUI",
    module_name = "NagramSessionBackupUI",
    srcs = glob([
        "**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/Display:Display",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/MtProtoKit:MtProtoKit",
        "//submodules/Postbox:Postbox",
        "//Nagram/SessionBackup:NagramSessionBackup",
        "//Nagram/Settings:NagramSettings",
        "//Nagram/Strings:NagramStrings",
    ],
    visibility = [
        "//visibility:public",
    ],
)
