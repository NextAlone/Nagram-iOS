load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

# MARK: NAGRAM — 会话导入的数据中心迁移解析测试。
# 被测函数在 TelegramCore 里（Api 与网络管线是 internal 的），所以测试放在这里
# 而不是 Tests/NagramSessionBackupTests——后者是零依赖的纯数据层，由
# scripts/test-session-backup-interop.sh 直接用 swiftc 编译。
swift_library(
    name = "NagramSessionMigrationTestsLib",
    testonly = True,
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    deps = [
        "//submodules/TelegramCore:TelegramCore",
    ],
)

ios_test_runner(
    name = "NagramSessionMigrationTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "NagramSessionMigrationTests",
    minimum_os_version = "13.0",
    runner = ":NagramSessionMigrationTestRunner",
    deps = [
        ":NagramSessionMigrationTestsLib",
    ],
    visibility = [
        "//visibility:public",
    ],
)
