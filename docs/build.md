# Build Notes

本文记录 Nagram-iOS 本地打包路径、环境约束，以及 2026-06-14 上游 rebase 后实机打包遇到的编译问题。

## 基本原则

- 仓库只支持整体构建 `Telegram/Telegram`，没有可靠的分模块 build。
- 每次 rebase / checkout 上游后先跑 `git submodule update --init --recursive`，并用 `git submodule status --recursive` 确认没有 `+` / `-` / `U` 前缀。
- `local.bazelrc` 是本机配置，已被 gitignore。`Make.py clean` / `bazel clean --expunge` 会删掉它，清理后需要重建。
- 真机包不要开启 `disableProvisioningProfiles`，否则主 app 签名配置会走 `None` 分支。
- 模拟器包可以在 `local.bazelrc` 中临时开启 `build --//Telegram:disableProvisioningProfiles`。
- 本机当前使用 Xcode 26.5 CLI toolchain。Xcode 27 beta 相关问题不要和业务代码错误混在一起排查。

## 推荐打包入口

真机 debug 包优先走 direct Bazel，绕开当前 `Make.py` debug 参数问题。先同步 submodule：

```sh
git submodule update --init --recursive
git submodule status --recursive
```

再打包：

```sh
source ~/.zshrc 2>/dev/null
build-input/bazel-8.4.2-darwin-arm64 build Telegram/Telegram \
  --keep_going \
  --announce_rc \
  --features=swift.use_global_module_cache \
  --verbose_failures \
  --remote_cache_async \
  --define=buildNumber=1 \
  --disk_cache="$HOME/telegram-bazel-cache" \
  -c dbg \
  --ios_multi_cpus=arm64 \
  --watchos_cpus=arm64_32
```

这个命令依赖 `build-system/Make/Make.py` 已经用 `build-input/local-configuration.json` 生成过 `build-input/configuration-repository/variables.bzl`。如果刚换 bundle id / team id / API 配置，需要先跑一次 Make.py 让配置落盘。

## 本机 local.bazelrc 关键项

当前本机需要保留这些方向：

```bazelrc
build --//Telegram:disableExtensions
build --repo_env=DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
build --repo_env=XCODE_VERSION=17F42
build --xcode_version_config=//build-input/xcode:host_xcodes
build --action_env=DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
build --host_action_env=DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
build --features=no_include_scanning
build --host_features=no_include_scanning
build --copt=-Wno-deprecated-declarations
build --@build_bazel_rules_swift//swift:copt=-no-warnings-as-errors
```

原因：

- `disableExtensions`：免费 Apple ID 避免扩展 App ID / provisioning 复杂度。
- `DEVELOPER_DIR` / `xcode_version_config`：强制使用 Xcode 26.5 CLI toolchain，避免被 Xcode 27 beta 接管。
- `no_include_scanning`：绕过 clang 21 + Bazel 8.x 的 absolute-path 依赖校验问题。
- `-Wno-deprecated-declarations` / `-no-warnings-as-errors`：minimum OS 提到 17.0 后，上游大量 iOS 15/16/17 deprecated API 会从 warning 变成 error。

## 2026-06-14 编译问题记录

### 1. Make.py 不接受 disableProvisioningProfiles 命令行参数

命令形态：

```sh
python3 build-system/Make/Make.py ... build ... --configuration=debug_sim_arm64 --disableProvisioningProfiles
```

失败现象：

```text
Make: error: unrecognized arguments: --disableProvisioningProfiles
```

结论：`disableProvisioningProfiles` 不是当前 `Make.py` 的直接参数。模拟器免签应放到 `local.bazelrc`：

```bazelrc
build --//Telegram:disableProvisioningProfiles
```

真机构建必须注释掉这一行。

### 2. Make.py debug 配置把 Swift 并发参数当成输入文件

命令形态：

```sh
python3 build-system/Make/Make.py ... build ... --configuration=debug_sim_arm64 --continueOnError
python3 build-system/Make/Make.py ... build ... --configuration=debug_arm64 --continueOnError
```

失败现象：

```text
error: unexpected input file: "-j"
error: unexpected input file: "14"
```

直接原因在 `build-system/Make/Make.py` 的 `common_debug_args`：

```py
'--@build_bazel_rules_swift//swift:copt="-j"',
f'--@build_bazel_rules_swift//swift:copt="{num_threads}"',
```

当前 rules_swift / Swift driver 会把这两个值传成异常输入。临时绕法是不用 `Make.py` 的 debug wrapper，改走 direct Bazel debug 命令。

### 3. release_arm64 触发 xcode-locator / strip 问题

命令形态：

```sh
python3 build-system/Make/Make.py ... build ... --configuration=release_arm64 --continueOnError
```

失败现象集中在 strip 阶段：

```text
ObjcBinarySymbolStrip ... Running '.../xcode-locator 26.5.0.17F42' failed
```

判断：release 配置额外启用 `dead_strip` / `objc_enable_binary_stripping`，strip action 仍会触发 xcode-locator。当前机器 LaunchServices 只稳定识别 Xcode 27 beta，虽然编译 action 已通过 `local.bazelrc` 指向 Xcode 26.5，strip 阶段仍可能失败。

临时绕法：先用 direct Bazel debug 真机包继续推进；release 包需单独修 xcode-locator / strip 路径。

### 4. TgVoipWebrtc / tgcalls 源码缺失

direct Bazel 真机 debug 已绕过上面两个 wrapper 问题，但继续暴露通话组件缺文件：

```text
missing input file '//submodules/TgVoipWebrtc:tgcalls/tgcalls/v2/CustomDcSctpSocket.cpp'
missing input file '//submodules/TgVoipWebrtc:tgcalls/tgcalls/v2/InstanceV2CompatImpl.cpp'
missing input file '//submodules/TgVoipWebrtc:tgcalls/tgcalls/group/GroupInstanceReferenceImpl.cpp'
fatal error: 'group/GroupInstanceReferenceImpl.h' file not found
```

判断：`submodules/TgVoipWebrtc/tgcalls` 是嵌套源码依赖；rebase / checkout 后该目录内容与 `submodules/TgVoipWebrtc/BUILD` 期望不一致。需要先确认 tgcalls 是否完整拉取、是否停在上游要求的版本，再决定是同步依赖还是调整 BUILD。

`--keep_going` 完整跑到最后后，最终汇总仍是 `Target //Telegram:Telegram failed to build`，末尾没有新增另一类硬错误；后续输出主要是 deprecated warning。

修复方式：

```sh
git submodule update --init --recursive submodules/TgVoipWebrtc/tgcalls
```

### 5. WebRTC submodule 未同步导致 FFmpeg 7 API 不匹配

同一轮 direct Bazel build 还暴露：

```text
third-party/webrtc/webrtc/modules/video_coding/codecs/h264/h264_decoder_impl.cc:237:13:
error: no member named 'reordered_opaque' in 'AVFrame'

error: no member named 'reordered_opaque' in 'AVCodecContext'
```

判断：这不是上游组合本身坏了，而是本地 `third-party/webrtc/webrtc` submodule 没同步。主仓库记录的新 WebRTC revision 已经把 `reordered_opaque` 换成 `AVPacket::pts` / `AVFrame::pts`。

修复方式：

```sh
git submodule update --init --recursive third-party/webrtc/webrtc
```

### 6. deprecated API 目前只是 warning

direct Bazel build 里可见大量 deprecated warning，例如：

```text
UIMenuController was deprecated in iOS 16.0
AVCaptureVideoOrientation was deprecated in iOS 17.0
kUTTypeImage was deprecated in iOS 15.0
```

这些目前不是阻塞项，因为 `local.bazelrc` 已把相关 warnings-as-errors 降回 warning。若清理后忘记恢复 `local.bazelrc`，它们会重新变成编译错误。

## 当前下一步

1. 新会话先跑全量 `git submodule update --init --recursive`。
2. 真机 debug 包走 direct Bazel 命令，产物为 `bazel-bin/Telegram/Telegram.ipa`。
3. release 包仍需单独处理 xcode-locator / strip 问题。
