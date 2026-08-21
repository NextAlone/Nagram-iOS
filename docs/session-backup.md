# 会话备份与恢复

本文记录 Nagram-iOS 的会话备份/恢复实现，以及与 [iebb/mithka](https://github.com/iebb/mithka) 的双向兼容格式。

## 入口

设置 → Nagram → 其他 → 会话备份（`Nagram.SessionBackup`）。页面提供三件事：

- 导出当前账号为 Pyrogram 会话串（复制到剪贴板）。
- 粘贴会话串新增账号，成功后自动切换到该账号。
- 把当前账号存入钥匙串（iCloud 钥匙串同步 / 仅本机），并可恢复、复制、删除。

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

## 代码位置

- `Nagram/SessionBackup/` — 纯数据层：会话串编解码、信封、钥匙串。零 Telegram 依赖，可独立编译测试。
- `Nagram/SettingsUI/NagramSessionBackupService.swift` — 桥接账号存储。导出走上游
  `accountBackupData(postbox:)`，导入通过 `AccountBackupData` + `transaction.createRecord`，
  不重复实现 MTProto 细节。
- `Nagram/SettingsUI/NagramSessionBackupController.swift` — 设置页 UI。

## 测试

```bash
scripts/test-session-backup-interop.sh --mithka ../mithka
```

脚本先跑 `Tests/NagramSessionBackupTests` 的单元测试，再做三方交叉验证：Nagram 的 Swift 编解码、
Python 写的 Pyrogram 参考实现、以及从本地 Mithka 检出里**原样抽取**的 Dart 解码器
（`Tests/NagramSessionBackupTests/Interop/extract_mithka_harness.py` 在临时目录生成，不会把
Mithka 源码复制进本仓库）。没装 dart 或没有 Mithka 检出时，相应阶段会跳过。
