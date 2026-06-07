load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: NAGRAM — Nagram 本地化模块。
# swift_library 提供 NagramLocalization；filegroup 把各语言 .strings 暴露给主 app 打包进 bundle。
swift_library(
    name = "NagramStrings",
    module_name = "NagramStrings",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AppBundle:AppBundle",
    ],
    visibility = [
        "//visibility:public",
    ],
)

filegroup(
    name = "NagramLocalizableStrings",
    srcs = glob(["Strings/*.lproj/NagramLocalizable.strings"]),
    visibility = [
        "//visibility:public",
    ],
)
