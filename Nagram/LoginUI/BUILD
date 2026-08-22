load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: NAGRAM — 登录页新增入口（扫码登录界面）。
# 上游只有一个隐藏的调试手势会画出二维码，这里补上真正的界面；
# 令牌交换仍然复用上游 TelegramCore 的实现。
swift_library(
    name = "NagramLoginUI",
    module_name = "NagramLoginUI",
    srcs = glob([
        "**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/ActivityIndicator:ActivityIndicator",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/QrCode:QrCode",
        "//Nagram/Strings:NagramStrings",
    ],
    visibility = [
        "//visibility:public",
    ],
)
