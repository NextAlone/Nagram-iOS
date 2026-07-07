load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "VerifyAlertController",
    module_name = "VerifyAlertController",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/ComponentFlow",
        "//submodules/Components/MultilineTextComponent",
        "//submodules/Components/BalancedTextComponent",
        "//submodules/Components/ComponentDisplayAdapters",
        "//submodules/TelegramUI/Components/TextFieldComponent",
        "//submodules/TextFormat",
        "//submodules/TelegramUI/Components/PremiumPeerShortcutComponent",
    ],
    visibility = [
        "//visibility:public",
    ],
)
