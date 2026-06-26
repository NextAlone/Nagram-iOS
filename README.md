# Nagram-iOS

> 基于 [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) 官方源码的第三方增强分支,对标 Android 端 [Nagram](https://github.com/NextAlone/Nagram),面向中文用户做功能增强与隐私强化。

## 项目说明

所有增强改动集中在仓库根的 `Nagram/` 目录(following upstream `SG*` naming convention),需要侵入上游的改动一律加锚注释 `// MARK: NAGRAM`,便于跟随上游同步。设置入口为「我的资料」下方的独立分组「Nagram」。

## 已实现功能

| 功能 | 说明 |
|---|---|
| 增强设置入口 | 设置页「我的资料」下方独立分组,进入 Nagram 设置页 |
| 强制复制(force-copy) | 在开启内容保护(禁止复制/转发)的对话中仍可复制消息文本,默认关闭 |
| 自定义图标与应用名 | 默认 Icon Composer (`.icon`) 图标,应用名为 Nagram |
| NagramSettings 基建 | 增强开关集中存储层 |

后续波次方向:纯 UI 开关(显示 ID/DC、时间戳显秒、隐藏手机号、贴纸尺寸等)→ 消息交互(上下文菜单逐项开关、双击消息动作)→ 翻译与 LLM/AI 集成 → 正则消息过滤、盘古之白。

## 构建

通过 Bazel 构建,统一用 `build-system/Make/Make.py` 包装脚本;不支持分模块构建,只能整体编译 `Telegram/Telegram` target。命令末尾的 `--continueOnError` 会透传 bazel 的 `--keep_going`,验证大范围改动时让全部错误一次暴露。

当前打包问题、Xcode/Bazel 环境约束和 2026-06-14 rebase 后编译记录见 [`docs/build.md`](docs/build.md)。

**每次 rebase / checkout 上游后先同步 submodule**，否则会出现 `tgcalls` 缺文件、WebRTC/FFmpeg API 不匹配等假错误：

```sh
git submodule update --init --recursive
git submodule status --recursive   # 确认没有 + / - / U 前缀
```

### 先选签名模式

`local.bazelrc` 是本机配置,已 gitignore;仓库根 `.bazelrc` 末尾会 `try-import %workspace%/local.bazelrc`。`bazel clean --expunge` / `Make.py clean` 会删掉它,清理后要按当前模式重建。

| 模式 | provisioning 状态 | `local.bazelrc` 里是否允许禁用扩展 |
|---|---|---|
| 正式/完整签名真机包 | 主 app + 6 个扩展都有 profile | **不允许**写 `build --//Telegram:disableExtensions` |
| 免费 Apple ID 自签 | 通常只有主 app profile | 可以写 `build --//Telegram:disableExtensions` |
| 模拟器免签 | 不需要 profile | 可以同时写 `build --//Telegram:disableProvisioningProfiles` 和 `build --//Telegram:disableExtensions` |

硬规则:

- 有正式/完整 provisioning 文件时,必须启用扩展;不要禁用 `Share`、`NotificationContent`、`NotificationService`、`Intents`、`Widget`、`BroadcastUpload`。
- 真机包永远不要写 `build --//Telegram:disableProvisioningProfiles`,否则主 app 签名会走 `None` 分支。
- `Make.py build` 不接受 `--disableProvisioningProfiles` / `--disableExtensions` 命令行参数;这些 Bazel flag 放进 `local.bazelrc`,或走 direct Bazel。

### 真机(正式/完整 provisioning)

仓库当前 `build-input/codesigning-development/profiles/` 已有完整 development profiles。用这套 profile 时,`local.bazelrc` 只能放 Xcode/toolchain/warning 相关配置,不能包含任何 `disableExtensions` / `disableProvisioningProfiles`。

完整签名至少需要这些 provisioning 目标:

- `Telegram`
- `Share`
- `NotificationContent`
- `NotificationService`
- `Intents`
- `Widget`
- `BroadcastUpload`

编译:

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

产物为 `bazel-bin/Telegram/Telegram.ipa`。安装到真机:

```sh
xcrun devicectl list devices
unzip -o bazel-bin/Telegram/Telegram.ipa -d /tmp/tg-device
xcrun devicectl device install app --device <DEVICE_UDID> /tmp/tg-device/Payload/Telegram.app
```

### 真机(免费 Apple ID 自签)

> 免费账号通常没有扩展 App ID / provisioning,所以这个模式才允许禁用扩展。免费证书 **7 天**到期,过期重跑 provisioning 生成步骤即可。

**1. 写 `build-input/local-configuration.json`**(`build-input/*` 已 gitignore,字段同官方 `build-system/template_minimal_development_configuration.json`):

```json
{
  "bundle_id": "com.example.nagram",
  "api_id": "<your_api_id>",
  "api_hash": "<your_api_hash>",
  "team_id": "<证书 OU 字段>",
  "app_center_id": "0",
  "is_internal_build": "true",
  "is_appstore_build": "false",
  "appstore_id": "0",
  "app_specific_url_scheme": "na",
  "premium_iap_product_id": "",
  "enable_siri": false,
  "enable_icloud": false
}
```

- `api_id` / `api_hash`:到 https://my.telegram.org/apps 申请自己的。
- `team_id`:不是证书名括号里的序列号,而是证书 subject 的 `OU` 字段。查:
  ```sh
  security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
  ```
  取其中 `OU=` 的值。
- `bundle_id`:用非官方 id(官方 id 仅 `ph.telegra.Telegraph` 等)。免费账号会自动把 entitlements 精简到仅剩 app-groups。

**2. 生成 provisioning**(免费账号只能由 Xcode 自动生成):Xcode 新建空项目,让 **Bundle Identifier 精确等于上面的 `bundle_id`**(Xcode 中 Bundle ID = Organization Identifier + Product Name),Team 选 Personal Team,run 到真机一次(顺带完成设备信任)。

**3. 把 provisioning 拷到 bazel 查找的路径**(Xcode 16+ 放在 UserData 下,bazel `local_provisioning_profile` 找传统路径):

```sh
cp ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision \
   ~/Library/MobileDevice/Provisioning\ Profiles/
```

**4. 免费自签的 `local.bazelrc` 只留扩展禁用项**(不能含 `disableProvisioningProfiles`,否则主 app 签名 select 走 None 分支失败):

```
build --//Telegram:disableExtensions
```

**5. 编译并安装**:

```sh
source ~/.zshrc 2>/dev/null
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-input/local-configuration.json \
  --xcodeManagedCodesigning --buildNumber=1 \
  --configuration=debug_arm64 --continueOnError
```

如果当前 `Make.py` debug wrapper 把 Swift `-j <n>` 当成输入文件,先确认它已经生成过 `build-input/configuration-repository/variables.bzl`,再走 direct Bazel:

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

产物为 `bazel-bin/Telegram/Telegram.ipa`。安装到真机:

```sh
xcrun devicectl list devices        # 查设备 UDID
unzip -o bazel-bin/Telegram/Telegram.ipa -d /tmp/tg-device
xcrun devicectl device install app --device <DEVICE_UDID> /tmp/tg-device/Payload/Telegram.app
```

首次启动需在 iPhone「设置 → 通用 → VPN 与设备管理」中信任开发者证书。

### 模拟器(免签,验证最快)

模拟器免签名 + 免扩展时,`local.bazelrc` 可以临时写:

```
build --//Telegram:disableProvisioningProfiles
build --//Telegram:disableExtensions
```

编译:

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-system/appstore-configuration.json \
  --xcodeManagedCodesigning --buildNumber=1 \
  --configuration=debug_sim_arm64 --continueOnError
```

产物为 `bazel-bin/Telegram/Telegram.ipa`(bundle id `ph.telegra.Telegraph`)。安装到已启动的模拟器:

```sh
unzip -o bazel-bin/Telegram/Telegram.ipa -d /tmp/tg-sim
# 装过旧版务必先卸载,否则旧 Frameworks dylib 不会被替换
xcrun simctl uninstall booted ph.telegra.Telegraph
xcrun simctl install booted /tmp/tg-sim/Payload/Telegram.app
```

---

以上为 Nagram-iOS 增强与构建说明。以下为上游 Telegram-iOS 的通用编译指南(原文保留):

# Telegram iOS Source Code Compilation Guide

We welcome all developers to use our API and source code to create applications on our platform.
There are several things we require from **all developers** for the moment.

# Creating your Telegram Application

1. [**Obtain your own api_id**](https://core.telegram.org/api/obtaining_api_id) for your application.
2. Please **do not** use the name Telegram for your app — or make sure your users understand that it is unofficial.
3. Kindly **do not** use our standard logo (white paper plane in a blue circle) as your app's logo.
3. Please study our [**security guidelines**](https://core.telegram.org/mtproto/security_guidelines) and take good care of your users' data and privacy.
4. Please remember to publish **your** code too in order to comply with the licences.

# Quick Compilation Guide

## Get the Code

```
git clone --recursive -j8 https://github.com/TelegramMessenger/Telegram-iOS.git
```

## Setup Xcode

Install Xcode (directly from https://developer.apple.com/download/applications or using the App Store).

## Adjust Configuration

1. Generate a random identifier:
```
openssl rand -hex 8
```
2. Create a new Xcode project. Use `Telegram` as the Product Name. Use `org.{identifier from step 1}` as the Organization Identifier.
3. Open `Keychain Access` and navigate to `Certificates`. Locate `Apple Development: your@email.address (XXXXXXXXXX)` and double tap the certificate. Under `Details`, locate `Organizational Unit`. This is the Team ID.
4. Edit `build-system/template_minimal_development_configuration.json`. Use data from the previous steps.

## Generate an Xcode project

```
python3 build-system/Make/Make.py \
    --cacheDir="$HOME/telegram-bazel-cache" \
    generateProject \
    --configurationPath=build-system/template_minimal_development_configuration.json \
    --xcodeManagedCodesigning
```

# Advanced Compilation Guide

## Xcode

1. Copy and edit `build-system/appstore-configuration.json`.
2. Copy `build-system/fake-codesigning`. Create and download provisioning profiles, using the `profiles` folder as a reference for the entitlements.
3. Generate an Xcode project:
```
python3 build-system/Make/Make.py \
    --cacheDir="$HOME/telegram-bazel-cache" \
    generateProject \
    --configurationPath=configuration_from_step_1.json \
    --codesigningInformationPath=directory_from_step_2
```

## IPA

1. Repeat the steps from the previous section. Use distribution provisioning profiles.
2. Run:
```
python3 build-system/Make/Make.py \
    --cacheDir="$HOME/telegram-bazel-cache" \
    build \
    --configurationPath=...see previous section... \
    --codesigningInformationPath=...see previous section... \
    --buildNumber=100001 \
    --configuration=release_arm64
```

# FAQ

## Xcode is stuck at "build-request.json not updated yet"

Occasionally, you might observe the following message in your build log:
```
"/Users/xxx/Library/Developer/Xcode/DerivedData/Telegram-xxx/Build/Intermediates.noindex/XCBuildData/xxx.xcbuilddata/build-request.json" not updated yet, waiting...
```

Should this occur, simply cancel the ongoing build and initiate a new one.

## Telegram_xcodeproj: no such package 

Following a system restart, the auto-generated Xcode project might encounter a build failure accompanied by this error:
```
ERROR: Skipping '@rules_xcodeproj_generated//generator/Telegram/Telegram_xcodeproj:Telegram_xcodeproj': no such package '@rules_xcodeproj_generated//generator/Telegram/Telegram_xcodeproj': BUILD file not found in directory 'generator/Telegram/Telegram_xcodeproj' of external repository @rules_xcodeproj_generated. Add a BUILD file to a directory to mark it as a package.
```

If you encounter this issue, re-run the project generation steps in the README.


# Tips

## Codesigning is not required for simulator-only builds

Nagram note: this upstream tip only applies to generating a simulator-only Xcode project. For current Nagram `Make.py build`, put `build --//Telegram:disableProvisioningProfiles` in `local.bazelrc`. Do not use it for device builds or when full provisioning profiles are present.

Upstream example:
```
python3 build-system/Make/Make.py \
    --cacheDir="$HOME/telegram-bazel-cache" \
    generateProject \
    --configurationPath=path-to-configuration.json \
    --codesigningInformationPath=path-to-provisioning-data \
    --disableProvisioningProfiles
```

## Versions

Each release is built using a specific Xcode version (see `versions.json`). The helper script checks the versions of the installed software and reports an error if they don't match the ones specified in `versions.json`. It is possible to bypass these checks:

```
python3 build-system/Make/Make.py --overrideXcodeVersion build ... # Don't check the version of Xcode
```
