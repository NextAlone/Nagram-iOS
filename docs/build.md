# Build Notes

本文记录 Nagram-iOS 本地打包路径、环境约束，以及 2026-06-14 上游 rebase 后实机打包遇到的编译问题。

## 基本原则

- 仓库只支持整体构建 `Telegram/Telegram`，没有可靠的分模块 build。
- 每次 rebase / checkout 上游后先跑 `git submodule update --init --recursive`，并用 `git submodule status --recursive` 确认没有 `+` / `-` / `U` 前缀。
- `local.bazelrc` 是本机配置，已被 gitignore。`Make.py clean` / `bazel clean --expunge` 会删掉它，清理后需要重建。
- 真机包永远不要开启 `disableProvisioningProfiles`，否则主 app 签名配置会走 `None` 分支。
- 有正式/完整 provisioning 文件时，必须启用扩展；不要写 `build --//Telegram:disableExtensions`。
- 只有免费 Apple ID 自签或模拟器免签时，才允许禁用扩展。
- 2026-09-19 检查时，`/Applications/Xcode.app` 已是 Xcode 27，包含 iOS 27 SDK。下文 Xcode 26.5 workaround 属于历史配置，使用前必须核对实际安装版本。

## UIScene 生命周期

Nagram 的单窗口 scene 入口位于 `Nagram/AppLifecycle/NagramSceneDelegate.swift`，通过 filegroup 编入 `TelegramUI`。`Telegram/BUILD` 和两个应用 plist 都声明了 `NagramSceneDelegate`。

- `AppDelegate` 在进程启动时初始化账户、推送和后台任务，以及不依赖 `UIWindow` 的展示宿主；后台唤醒不需要先连接 scene。
- scene 连接时创建 `UIWindow(windowScene:)`；断开时释放窗口，保留账户和展示状态供重连复用。
- 前后台状态、冷/热启动 URL、Universal Links 和快捷操作从 scene 转发；通知响应继续由 `UNUserNotificationCenterDelegate` 处理，避免重复消费。
- 不要再让根控制器覆盖 `windowScene.delegate`。
- iOS 27 的键盘窗口通过当前 scene 的 `keyboardSceneDelegate.keyboardWindow` 获取；旧的 `remoteKeyboardWindowForScreen:create:` 会触发系统断言，只保留给较早系统使用。

Xcode 更新后，本地 `build-input/xcode/BUILD` 声明可能与实际工具链不符。不要仅凭 IPA 的 `DTSDKName` 判断 SDK；用 `xcrun vtool -show-build <Telegram.app/Telegram>` 检查 Mach-O 的 `LC_BUILD_VERSION`。iOS 27 SDK 构建的包必须接入 scene 生命周期。

UI 回归用例 `UITests/testSceneForegroundRoundTrip` 使用 `--ui-test` 隔离数据，检查启动、输入、前后台往返和键盘恢复；`UITests/testSceneColdURL` 检查冷启动链接打开代理预览，不启用代理。链接处理需要等待账户界面 `isReady`，避免 scene 连接早于界面展示时丢失操作。

生成工程缓存缺失时，按 README 重新运行 `Make.py generateProject` 后再测试。旧 DerivedData 的构建记录可能遗漏 Bazel 输出，遇到框架产物不存在时可用新的 `-derivedDataPath`。本机启用 Nix 时，给 `xcodebuild` 设置 `PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin`，否则 GNU `find` 无法执行生成脚本的 BSD `find -depth 2` 参数。

2026-09-19 使用 Xcode 27 / iOS 27 模拟器运行以上两个 UI 用例，均通过。最终 `debug_arm64` 包 33235 使用完整签名，保留全部 6 个扩展，已在 iOS 27.2 真机安装并启动。真机回归覆盖启动、前后台往返和热链接；远程通知、CallKit、系统后台唤醒和 scene 被系统回收后的重连尚未做端到端验证。

## 签名模式选择

| 模式 | provisioning 状态 | 扩展策略 | provisioning 策略 |
|---|---|---|---|
| 正式/完整签名真机包 | 主 app + 6 个扩展都有 profile | 必须启用扩展 | 必须启用 provisioning |
| 免费 Apple ID 自签 | 通常只有主 app profile | 允许禁用扩展 | 必须启用 provisioning |
| 模拟器免签 | 不需要 profile | 允许禁用扩展 | 允许禁用 provisioning |

## 真机构建强制预检

收到“真机打包”“真机构建”或“安装到 iPhone”请求时，必须先完成以下检查，再选择签名模式：

1. 完整阅读本页的“签名模式选择”、本节、“在 workspace / worktree 构建真机包”和对应签名模式章节。
2. 检查目标设备是否已连接且 paired。
3. 检查 Keychain 中的 Apple Development identity。
4. 检查主 app 与 6 个扩展的 provisioning profiles；必须核对 profile 类型、Team ID、Application Identifier 和有效期，不能只按文件数量判断。
5. 检查当前 jj workspace 的 `build-input/local-configuration.json`、`build-input/codesigning-development/` 和 `local.bazelrc`。
6. 检查 `build-system/bazel-rules/` 等构建依赖目录是否已物化。
7. 只有以上事实明确后，才能选择完整签名、免费 Apple ID 自签或模拟器免签。

硬规则：

- 隔离 jj workspace 中缺少 gitignored `build-input`，**不等于**只能免费自签。应先从操作者明确许可的私有来源恢复签名输入；未经许可不得访问其他 workspace。
- 如果主 app 与 6 个扩展 profile 齐全，必须走完整签名，不得设置 `disableExtensions` 或 `disableProvisioningProfiles`。
- 只有完整 profiles 确实不可用且用户明确要求免费 Apple ID 自签时，才允许禁用扩展；真机包始终不得禁用 provisioning。
- Bazel rule/submodule 目录为空属于依赖未物化，不能通过切换签名模式规避。若恢复依赖需要 `git` 命令，jj-only agent 必须先取得该具体命令的当次授权。
- 完成标准是 IPA 生成、`devicectl` 安装成功且设备端安装结果已验证；仅构建成功不算完成。

完整签名至少需要这些 provisioning 目标：

- `Telegram`
- `Share`
- `NotificationContent`
- `NotificationService`
- `Intents`
- `Widget`
- `BroadcastUpload`

`build-input/*` 已被 gitignore，新建的隔离 jj workspace 不保证自带签名输入。若当前 workspace 缺失，应先按“在 workspace / worktree 构建真机包”从操作者许可的私有来源恢复；恢复后主 app 与 6 个扩展 development profiles 齐全时，必须使用“正式/完整签名真机包”模式，不能禁用扩展。

## local.bazelrc 模板

`local.bazelrc` 可以放 Xcode/toolchain/warning workaround，但签名相关 flag 必须按模式写。

正式/完整签名真机包：

```bazelrc
# 不写 disableExtensions
# 不写 disableProvisioningProfiles
```

免费 Apple ID 自签：

```bazelrc
build --//Telegram:disableExtensions
# 不写 disableProvisioningProfiles
```

模拟器免签：不改 `local.bazelrc`，给 `Make.py build` 加 `--disableProvisioningProfiles --disableExtensions`（见“模拟器免签”）。

本机常用 toolchain workaround 可按需追加：

```bazelrc
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

- `DEVELOPER_DIR` / `xcode_version_config`：强制使用 Xcode 26.5 CLI toolchain，避免被 Xcode 27 beta 接管。
- `no_include_scanning`：绕过 clang 21 + Bazel 8.x 的 absolute-path 依赖校验问题。
- `-Wno-deprecated-declarations` / `-no-warnings-as-errors`：minimum OS 提到 17.0 后，上游大量 iOS 15/16/17 deprecated API 会从 warning 变成 error。

## 正式/完整签名真机包

完整签名是真实 Apple Development 证书 + 主 app + 6 个 extension provisioning profiles 的模式。`local.bazelrc` 可以不存在；不存在等价于不禁用扩展、不禁用 provisioning profiles。如果存在，也不得包含任何 `disableExtensions` / `disableProvisioningProfiles`。

必须先补齐当前 checkout 下的签名输入：

```text
build-input/local-configuration.json
build-input/codesigning-development/
```

`build-input/local-configuration.json` 字段同 `build-system/template_minimal_development_configuration.json`。其中 `bundle_id` 必须和主 app provisioning profile 匹配，`team_id` 必须是证书 / profiles 所属团队的 Team ID。

`build-input/codesigning-development/profiles/` 至少需要 7 个 `.mobileprovision`，分别覆盖：

- `Telegram`
- `Share`
- `NotificationContent`
- `NotificationService`
- `Intents`
- `Widget`
- `BroadcastUpload`

本地打包通常直接使用 Keychain 里的 Apple Development identity；只有需要在构建流程中导入证书的环境，才把 `.p12` 等证书材料放到 `build-input/codesigning-development/certs/`。

打包前可先检查：

```sh
test -f build-input/local-configuration.json
test -d build-input/codesigning-development/profiles
find build-input/codesigning-development/profiles -name '*.mobileprovision' | wc -l
security find-identity -v -p codesigning | grep "Apple Development"
```

编译：

```sh
source ~/.zshrc 2>/dev/null
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-input/local-configuration.json \
  --codesigningInformationPath build-input/codesigning-development \
  --buildNumber=1 \
  --configuration=debug_arm64 --continueOnError
```

产物：

```text
bazel-bin/Telegram/Telegram.ipa
```

安装：

```sh
xcrun devicectl list devices
unzip -o bazel-bin/Telegram/Telegram.ipa -d /tmp/tg-device
xcrun devicectl device install app --device <DEVICE_UDID> /tmp/tg-device/Payload/Telegram.app
```

## 免费 Apple ID 自签

免费账号通常没有 6 个扩展 profile，所以这个模式允许禁用扩展，但仍然必须保留主 app provisioning：

```bazelrc
build --//Telegram:disableExtensions
```

`build-input/local-configuration.json` 字段同 `build-system/template_minimal_development_configuration.json`。注意：

- `team_id` 是 Apple Development 证书 subject 的 `OU` 字段，不是证书名括号里的序列号。
- `bundle_id` 用非官方 id，并让 Xcode 空项目的 Bundle Identifier 与它完全一致。
- Xcode 生成的 `.mobileprovision` 需要拷到 Bazel 查找的传统路径：

```sh
cp ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision \
   ~/Library/MobileDevice/Provisioning\ Profiles/
```

编译：

```sh
source ~/.zshrc 2>/dev/null
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-input/local-configuration.json \
  --xcodeManagedCodesigning --buildNumber=1 \
  --configuration=debug_arm64 --continueOnError
```

## 在 workspace / worktree 构建真机包

这里的 workspace / worktree 指 `.workspaces/<name>`、`.worktrees/<name>` 这类独立 checkout。真机构建必须在对应 checkout 根目录执行；`build-input/*` 和 `local.bazelrc` 都按当前 Bazel workspace root 解析，不会自动读取主 checkout 的 gitignored 文件。

如果检查结果类似下面这样，说明当前 workspace / worktree 缺签名输入，不能直接打真实证书真机包：

```text
local.bazelrc: 不存在
build-input/local-configuration.json: 不存在
build-input/codesigning-development: 不存在
~/Library/MobileDevice/Provisioning Profiles: 0 个 profile
Keychain: 有 Apple Development identity
```

其中 `local.bazelrc` 对正式/完整签名不是必需项；缺它不等于错误，只表示不额外禁用扩展和 provisioning profiles。必须补的是：

```text
build-input/local-configuration.json
build-input/codesigning-development/
```

主 checkout 已有这些输入时，可以从 `default` workspace 或主仓库目录复制 / 链接过来。先在目标 workspace / worktree 根目录确定来源目录 `PRIMARY`。

从 `jj` 的 `default` workspace 读取：

```sh
PRIMARY="$(jj workspace list -T 'if(name == "default", root ++ "\n", "")' | head -n 1)"
test -n "${PRIMARY}" || {
  echo "default workspace path not found" >&2
  exit 1
}
```

如果当前目录就是主仓库下的 `.worktrees/<name>` 或 `.workspaces/<name>`，也可以直接取上两级作为主仓库：

```sh
PRIMARY="$(cd ../.. && pwd)"
```

或者手写主仓库路径：

```sh
PRIMARY=/Volumes/Repository/iOS/Nagram-ios
```

一次性复制签名输入：

```sh
mkdir -p build-input

cp -f "${PRIMARY}/build-input/local-configuration.json" build-input/local-configuration.json

if test -e build-input/codesigning-development; then
  mv build-input/codesigning-development "build-input/codesigning-development.bak.$(date +%Y%m%d%H%M%S)"
fi
cp -R "${PRIMARY}/build-input/codesigning-development" build-input/codesigning-development

if test -f "${PRIMARY}/local.bazelrc"; then
  cp -f "${PRIMARY}/local.bazelrc" local.bazelrc
fi
```

如果希望后续随主仓库签名配置更新，也可以改用 symlink：

```sh
mkdir -p build-input

for path in \
  build-input/local-configuration.json \
  build-input/codesigning-development
do
  test -e "${PRIMARY}/${path}" || {
    echo "missing ${PRIMARY}/${path}" >&2
    exit 1
  }
  ln -sfn "${PRIMARY}/${path}" "${path}"
done

if test -e "${PRIMARY}/local.bazelrc"; then
  ln -sfn "${PRIMARY}/local.bazelrc" local.bazelrc
fi
```

如果目标 checkout 已经有同名普通文件或目录，先确认内容并移走后再复制 / 链接，不要覆盖未知证书或配置。

如果需要使用 direct Bazel fallback，或 `local.bazelrc` 引用了本地 `build-input/xcode` 配置，再从同一个 `PRIMARY` 补下面这些本地构建输入。一次性复制：

```sh
for path in \
  build-input/bazel-8.4.2-darwin-arm64 \
  build-input/configuration-repository \
  build-input/configuration-repository-workdir \
  build-input/xcode
do
  test -e "${PRIMARY}/${path}" || {
    echo "missing ${PRIMARY}/${path}" >&2
    exit 1
  }
  if test -e "${path}"; then
    mv "${path}" "${path}.bak.$(date +%Y%m%d%H%M%S)"
  fi
  cp -R "${PRIMARY}/${path}" "${path}"
done
```

或者继续使用 symlink：

```sh
for path in \
  build-input/bazel-8.4.2-darwin-arm64 \
  build-input/configuration-repository \
  build-input/configuration-repository-workdir \
  build-input/xcode
do
  test -e "${PRIMARY}/${path}" || {
    echo "missing ${PRIMARY}/${path}" >&2
    exit 1
  }
  ln -sfn "${PRIMARY}/${path}" "${path}"
done
```

`configuration-repository*` 是 `Make.py` 生成的本地配置仓库；复制 / 链接它们后 direct Bazel fallback 可以直接复用主 checkout 已生成的 `variables.bzl`。如果选择不补它们，就先在当前 checkout 跑一次 `Make.py build`，让它重新生成后再走 direct Bazel。

补齐后，在该 workspace / worktree 根目录按签名模式执行真机命令：正式/完整签名用 `--codesigningInformationPath build-input/codesigning-development`；免费 Apple ID 自签用 `--xcodeManagedCodesigning`。产物仍是当前 checkout 下的 `bazel-bin/Telegram/Telegram.ipa`。安装也在同一个 checkout 根目录执行：

```sh
xcrun devicectl list devices
unzip -o bazel-bin/Telegram/Telegram.ipa -d /tmp/tg-device
xcrun devicectl device install app --device <DEVICE_UDID> /tmp/tg-device/Payload/Telegram.app
```

注意：真机包仍然不能在 `local.bazelrc` 中开启 `disableProvisioningProfiles`。使用完整 development profiles 时，也不能开启 `disableExtensions`。

## 模拟器免签

模拟器模式禁用 provisioning 和扩展，通过 `Make.py build` 的命令行参数开启；不要为此修改 `local.bazelrc`，它保持真机签名模式即可。`--disableProvisioningProfiles` 只接受 `debug_sim_arm64` / `release_sim_arm64`，真机配置会直接报错。

编译：

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-system/appstore-configuration.json \
  --xcodeManagedCodesigning --buildNumber=1 \
  --configuration=debug_sim_arm64 --continueOnError \
  --disableProvisioningProfiles --disableExtensions
```

安装：

```sh
unzip -o bazel-bin/Telegram/Telegram.ipa -d /tmp/tg-sim
xcrun simctl uninstall booted ph.telegra.Telegraph
xcrun simctl install booted /tmp/tg-sim/Payload/Telegram.app
```

## Direct Bazel fallback

如果 `Make.py` debug wrapper 触发 Swift `-j <n>` 问题，先让 `Make.py` 按目标签名模式生成过 `build-input/configuration-repository/variables.bzl`，再走 direct Bazel：

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

这个 fallback 复用当前 `local.bazelrc`，所以切换正式/免费签名模式时仍要先改对签名 flag。模拟器模式不改 `local.bazelrc`，直接在命令行追加 `--//Telegram:disableProvisioningProfiles --//Telegram:disableExtensions`。

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

当时的结论：`disableProvisioningProfiles` 不是 `Make.py build` 的直接参数，只能写进 `local.bazelrc`。

现状：`Make.py build` 已支持 `--disableProvisioningProfiles` 和 `--disableExtensions`，模拟器免签直接加这两个参数，不再修改 `local.bazelrc`。

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
