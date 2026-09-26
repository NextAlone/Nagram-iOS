# 宣传截图 Demo 模式

用 `--demo` 启动 Nagram，无需登录即可进入纯模拟聊天列表。界面使用真实 Telegram / Nagram 组件，可以进入聊天、打开设置和调整主题。

每次 demo 启动默认使用经典亮色主题，关闭自动深色切换，不跟随系统深色模式。可以在演示设置中临时调整主题；正常账号的主题设置不受影响。

## 启动

在 Xcode Scheme 的 **Run → Arguments → Arguments Passed On Launch** 中添加 `--demo`。也可以对已安装的模拟器 app 执行：

```sh
xcrun simctl launch --terminate-running-process booted ph.telegra.Telegraph --demo
```

自定义签名包请将 `ph.telegra.Telegraph` 替换为实际 Bundle ID。不要同时传入 `--ui-test`。

### 中文和英文文案

默认使用中文模拟内容。通过 `--demo-language zh` / `--demo-language en` 选择版本，个人名称、群组名、频道名和全部消息会一起切换，两版的布局、时间和未读数相同。

```sh
xcrun simctl launch --terminate-running-process booted ph.telegra.Telegraph --demo --demo-language zh
xcrun simctl launch --terminate-running-process booted ph.telegra.Telegraph --demo --demo-language en
```

Xcode Scheme 中将 `--demo-language` 和 `en` 分别添加为启动参数。该参数只影响模拟内容；菜单、日期标签等界面文字仍使用 app 的语言设置。省略参数即为 `zh`，缺少值或使用其他值会报告启动错误。

## 截图

模拟数据包含虚构个人账号、个人聊天、群组、频道和收藏夹；头像使用原生姓名占位图。聊天内容、置顶顺序和初始未读数固定，消息日期使用启动当天，最新消息时间为 09:41。打开聊天会像正常 app 一样改变已读状态，重新启动 `--demo` 即可重置。

可在模拟器中统一状态栏后截图：

```sh
xcrun simctl status_bar booted override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl io booted screenshot /tmp/nagram-demo.png
xcrun simctl status_bar booted clear
```

Demo 用于本地界面展示。发送消息、翻译、远程主题、媒体下载等需要服务器的操作不能完成。截图中的在线连接状态仅用于展示，不代表已连接 Telegram。

## 隔离与退出

- 演示账号和 Telegram 设置保存在 app group 下独立的 `nagram-demo-data/` 目录，每次 demo 启动都会重建。
- Nagram 开关使用独立的 `nagram.screenshot-demo` UserDefaults suite，不向 iCloud 同步；它们会在 demo 重启后保留。
- 演示账号禁止 MTProto 主连接、上传下载连接和地址发现，不注册推送，不同步设备通讯录。
- 不带 `--demo` 重新启动，即恢复正常账号与设置；正式账号数据库不会被演示数据写入。

模拟内容集中在 `Nagram/Demo/Sources/NagramDemo.swift`，可修改文案和聊天样例后重新构建。
