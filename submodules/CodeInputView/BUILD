load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "CodeInputView",
    module_name = "CodeInputView",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
    ],
    deps = [
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
    	"//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/PhoneNumberFormat:PhoneNumberFormat",
    ],
    visibility = [
        "//visibility:public",
    ],
)
