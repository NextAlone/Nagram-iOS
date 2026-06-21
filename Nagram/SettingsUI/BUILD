load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: NAGRAM — Nagram 增强设置页 UI 层（ItemListController toggle）。
# 依赖数据层 Nagram/Settings + 上游 UI 模块；rebase 时上游碰不到 Nagram/。
swift_library(
    name = "NagramSettingsUI",
    module_name = "NagramSettingsUI",
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
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/UndoUI:UndoUI",
        "//Nagram/Settings:NagramSettings",
        "//Nagram/Strings:NagramStrings",
        "//Nagram/SettingsSignal:NagramSettingsSignal",
        # MARK: NAGRAM — 贴纸尺寸滑杆(SliderComponent,复刻省电模式粗轨道)
        "//submodules/AsyncDisplayKit",
        "//submodules/ComponentFlow",
        "//submodules/TelegramUI/Components/FaceScanScreen",
        "//submodules/TelegramUI/Components/SliderComponent",
    ],
    visibility = [
        "//visibility:public",
    ],
)
