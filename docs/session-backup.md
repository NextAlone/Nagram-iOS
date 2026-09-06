# 会话备份与恢复

本文记录 Nagram-iOS 的会话备份/恢复实现，以及与 [iebb/mithka](https://github.com/iebb/mithka) 的双向兼容格式。

## 入口

### 已登录：设置页

设置 → Nagram → 其他 → 会话备份（`Nagram.SessionBackup`）。页面提供三件事：

- 导出当前账号为 Pyrogram 会话串（复制到剪贴板）。
- 粘贴会话串新增账号，成功后自动切换到该账号。
- 把当前账号存入钥匙串（iCloud 钥匙串同步 / 仅本机），并可恢复、复制、删除。

设置 → Nagram 里另有一个 iCloud 同步开关（`nagram.sessionBackupICloudSync`，默认开）。
关掉之后所有读写只走 local 那个 service，已同步的条目不再被列出，也不再新增同步条目。

### 首次启动：登录页

全新安装时还没有账号，设置页不可达，所以登录首屏（Splash，"Start with Nagram" 那一屏）和
手机号输入页的右上角都放了一个账号按钮，点开是一个三项菜单：

1. **扫码登录** — `NagramQrLoginController`，见下。
2. **导入会话** — 打开只做导入的精简页面：粘贴会话串，或直接点选钥匙串里已同步过来的备份。
3. **已保存的账号（N）** — `NagramSavedAccountsController`，列出钥匙串里存在、但本机没登录的账号，
   点一个直接恢复。N 为该数量，同时以红点角标显示在按钮上；为 0 时这一项和角标都不出现。

两个入口共用 `NagramLoginOptionsButton`（含角标与图标），呈现逻辑集中在
`AuthorizationSequenceController`——只有那里拿得到 `SharedAccountContext`。

两处入口的差别只在于上下文：

| | 设置页 | 登录页 |
| --- | --- | --- |
| 依赖 | `AccountContext` | 仅 `SharedAccountContext` |
| 导入后 | `switchToAccount` 切号 | `setCurrentId` + `removeAuth`，登录流程自行结束 |
| 功能 | 导出 + 导入 + 钥匙串管理 | 扫码 / 导入 / 恢复 |

导入后不采用会话串里的 `apiId`（原因见下），登录页那条路径与上游手机号登录完成时做的事一致
（见 `TelegramCore/Sources/Authorization.swift`）。

### 扫码登录

`Nagram/LoginUI/NagramQrLoginController.swift`。令牌交换复用上游 TelegramCore 的实现，
这里补的是界面——上游只有一个隐藏的调试手势会画出二维码。

两个容易踩的点：

- **令牌请求要自带重试。** 冷启动时首个请求常见 `CONNECTION_NOT_INITED`，没有错误分支的话
  界面就是一个永远不会填充的空白方块。这里每 3 秒重试一次。
- **确认之后到登录完成之间有空窗。** 手机上点了确认，客户端还要拉账号状态、可能再要两步验证密码，
  实测能有十秒。用 `hasBeenAccepted` 标记切到"正在登录"文案，不然用户以为扫失败了。

## Pyrogram 会话串

271 字节裸数据，base64url 编码、去掉 padding（规范输出固定 362 字符）。与 Pyrogram 的
`SESSION_STRING_FORMAT = ">BI?256sQ?"` 完全一致：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| 0 | 1 | `dcId` | 主数据中心，非 0 |
| 1 | 4 | `apiId` | 大端 uint32，非 0 |
| 5 | 1 | `testMode` | 0 / 1 |
| 6 | 256 | `authKey` | MTProto 授权密钥，不可全 0 |
| 262 | 8 | `userId` | 大端 uint64，非 0 |
| 270 | 1 | `isBot` | 0 / 1 |

解码时容忍 padding、首尾空白与标准 base64 字母表；编码只输出上面的规范形式。

会话串本身不携带 `authKeyId`，导入时按 MTProto 的做法重新推导：`SHA1(authKey)` 的末 8 字节按
小端读成 int64（见 `PyrogramSessionString.authKeyId(sha1Digest:)`，哈希用 `MTSha1`）。

## 备份信封

钥匙串条目与导出文件使用 Mithka 的 JSON 信封，`format` 标识符也保持不变——Mithka 的解码器会
拒绝其他标识符，保留它才能双向读取：

```
format        mithka.tdlib.session_string.v2.explicit_consent   （另兼容读取 v1）
id/accountId  用户 ID 字符串
userId        用户 ID
name / phone  显示名与手机号（phone 可为 null）
storage       synced / local
createdAt     UTC ISO8601，带毫秒，形如 2026-08-20T11:22:33.444Z
sessionString 上面的会话串
slot          Mithka 的本地槽位，Nagram 无此概念，恒为 0（Mithka 解码时忽略）
```

## 钥匙串布局

与 Mithka 的 iOS 插件一致：`kSecClassGenericPassword`，`service` 为
`<bundleId>.sessionsbackup`（synced：`kSecAttrSynchronizable` + `WhenUnlocked`）或
`<bundleId>.sessionsbackup.local`（local：仅本机 + `AfterFirstUnlockThisDeviceOnly`），
`account` 为用户 ID，值为上面的 JSON。

钥匙串条目按 bundle id 隔离，两个 app 无法直接读到对方的条目；跨 app 迁移走会话串或导出的
信封 JSON。钥匙串备份的作用是在用户自己的设备之间同步。

## api_id 的处理

导入时不采用会话串里的 `apiId`。MTProto 的授权密钥绑定的是数据中心而不是 api_id，本 app 始终
用自己的 `BuildConfig.apiId` 建连。因此导出的串带 Nagram 的 api_id，导入进来的账号也继续以
Nagram 的 api_id 运行。

## 数据中心迁移

会话串里的 `dcId` 是**这把密钥所属的**数据中心，不一定是账号的归属（home）数据中心——
Pyrogram 之外的实现（包括 Mithka）可能导出一把非归属 DC 的密钥。直接拿它当归属 DC 建连，
所有请求都会被 `303 USER_MIGRATE_N` 顶回来。

`submodules/TelegramCore/Sources/Account/NagramSessionMigration.swift` 处理这件事：

1. `nagramHomeDatacenterId` 发一个 `updates.getState` 探针，从 `303` 错误里读出归属 DC。
   探针必须直接构造 `MTRequest` 并设 `shouldContinueExecutionWithErrorContext = { _ in false }`；
   走 `Network.request` 的话，它内部的重试钩子会吞掉 303，请求永远不返回。
2. 探针要选一个**只有归属 DC 能回答**的方法。`users.getUsers` 任何 DC 都答得出来，
   用它探不到迁移。
3. 拿到归属 DC 后等 MtProtoKit 通过 `auth.exportAuthorization` / `importAuthorization`
   把授权搬过去（`MTContext.authTokenForDatacenter`，不是 `authInfoForDatacenter`——
   后者只是新建一把密钥，不会转移授权）。
4. 超时（30 次 × 1 秒）就丢弃这条记录并明确报错，不留一个连不上的账号。

`makeCurrent` 必须放在**第二个** `AccountManager` 事务里。和 `createRecord` 挤在同一个事务里，
登录流程会在迁移完成前就被拆掉，迁移把自己取消掉。

> 已知未覆盖：第 3 步（跨 DC 授权转移真的成功）没有端到端验证过——手上的测试会话串正是
> 一把非归属 DC 的密钥，而 Telegram 把 `auth.exportAuthorization` 本身也路由到归属 DC，
> 于是 31 次尝试全部返回 `303 USER_MIGRATE_1`，任何客户端都无法用它自举。失败路径
> （探针、303 解析、超时丢弃、报错文案）是验证过的。

## 代码位置

- `Nagram/SessionBackup/` — 纯数据层：会话串编解码、信封、钥匙串。零 Telegram 依赖，可独立编译测试。
- `Nagram/SessionBackupUI/NagramSessionBackupService.swift` — 桥接账号存储。导出走上游
  `accountBackupData(postbox:)`，导入通过 `AccountBackupData` + `transaction.createRecord`，
  不重复实现 MTProto 细节。导入只需要 `SharedAccountContext`，这是登录页也能用的前提。
- `Nagram/SessionBackupUI/NagramSessionBackupController.swift` — 设置页 UI（需要账号）。
- `Nagram/SessionBackupUI/NagramSessionImportController.swift` — 登录页 UI（无账号，
  用 `ItemListController` 不带 context 的构造器）。
- `Nagram/SessionBackupUI/NagramSavedAccountsController.swift` — 钥匙串账号选择页。
- `Nagram/LoginUI/` — 登录页新增的界面：扫码登录、右上角账号按钮（含红点角标）。
- `submodules/TelegramCore/Sources/Account/NagramSessionMigration.swift` — 归属 DC 探测与迁移。

UI 层单独成模块而不是塞进 `Nagram/SettingsUI`，是为了让 `AuthorizationUI` 依赖它时
不会把整个设置页（含 FaceScanScreen、SliderComponent 等）拖进登录流程。

上游改动都带 `// MARK: NAGRAM`，集中在 `AuthorizationUI`：`BUILD`（依赖）、
`AuthorizationSequenceSplashController.swift` 与 `AuthorizationSequencePhoneEntryController.swift`
（各挂一个账号按钮，只持有回调），以及 `AuthorizationSequenceController.swift`
（真正呈现菜单与各个页面，那里才有 `SharedAccountContext`）。

两个按钮都用 overlay subview，而不是 `UIBarButtonItem`：Splash 没有导航栏，手机号页左上角是
返回按钮、右上角在"再加一个账号"时才是关闭按钮，占用它会让用户退不回去。

顺带修了一个上游既有的问题（`AuthorizationSequencePhoneEntryController`）：`viewWillAppear`
无条件把 Splash 的快照钉到手机号页上，而负责把它们动画移除的 `animateIn(...)` 却只在
`layout.inputHeight > 0`（软键盘出现）时才被调用。模拟器接了硬件键盘时软键盘永不出现，
快照就永久留在屏幕上，看起来像"Start with Nagram"点了没反应。现在两个调用点都过
`nagramRunPendingTransitionIn()`，并在 `viewDidAppear` 里加了 1 秒兜底。

## 测试

```bash
scripts/test-session-backup-interop.sh --mithka ../mithka
```

脚本先跑 `Tests/NagramSessionBackupTests` 的单元测试，再做三方交叉验证：Nagram 的 Swift 编解码、
Python 写的 Pyrogram 参考实现、以及从本地 Mithka 检出里**原样抽取**的 Dart 解码器
（`Tests/NagramSessionBackupTests/Interop/extract_mithka_harness.py` 在临时目录生成，不会把
Mithka 源码复制进本仓库）。没装 dart 或没有 Mithka 检出时，相应阶段会跳过。

这一套用 `swiftc` 直接编译，不走 Bazel——`Nagram/SessionBackup/` 是零依赖的纯数据层，正好如此。
迁移错误的解析在 TelegramCore 里（`Api` 与网络管线是 internal 的），所以另有一个 Bazel 测试目标：

```bash
python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache \
  test --configurationPath build-system/appstore-configuration.json --xcodeManagedCodesigning \
  --target //Tests/NagramSessionMigrationTests:NagramSessionMigrationTests
```

它已登记进 `Tests/AllTests`，所以默认的 `Make.py test` 也会跑到。
