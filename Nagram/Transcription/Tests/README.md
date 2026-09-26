# STT 独立测试

这些命令在 macOS/Xcode 环境从仓库根目录执行，不使用真实 Keychain/UserDefaults，不需要外部 API Key。配置测试没有网络请求；provider 测试仅访问 Python 启动的 loopback HTTP mock。

测试直接编译生产配置源码与生产 provider 源码，使用仓库实际 SwiftSignalKit。仅配置入口依赖的 Settings/Keychain 使用 `ConfigurationTests.swift` 内存桩。它们不会构建、签名或安装 iOS App，也不覆盖聊天媒体解码、数据库、UIKit 或物理设备行为。

## 配置测试

```sh
mkdir -p /tmp/nagram-stt-tests/cache
xcrun swiftc -swift-version 5 \
  -module-cache-path /tmp/nagram-stt-tests/cache \
  Nagram/Settings/NagramSTTConfiguration.swift \
  Nagram/Transcription/Tests/ConfigurationTests.swift \
  -o /tmp/nagram-stt-tests/configuration
/tmp/nagram-stt-tests/configuration
```

预期输出：

```text
PASS: 55 STT configuration assertions (real configuration source; in-memory credential/settings stubs).
```

覆盖默认与自定义 URL、`/v1` 去重、代理前缀、IPv6、完整 Endpoint/query、字段 trim、语言、模型与 credential 校验、配置快照、credential 读取错误传播与恢复。

## 生产 provider 的本地 mock 测试

先编译仓库 SwiftSignalKit，以及包含真实配置构造器和测试存储桩的 `NagramSettings` 模块：

```sh
mkdir -p /tmp/nagram-stt-tests/cache
xcrun swiftc -swift-version 5 \
  -module-cache-path /tmp/nagram-stt-tests/cache \
  -emit-library -emit-module -module-name SwiftSignalKit \
  submodules/SSignalKit/SwiftSignalKit/Source/*.swift \
  -o /tmp/nagram-stt-tests/libSwiftSignalKit.dylib \
  -emit-module-path /tmp/nagram-stt-tests/SwiftSignalKit.swiftmodule

xcrun swiftc -swift-version 5 \
  -module-cache-path /tmp/nagram-stt-tests/cache \
  -D STT_LIBRARY -emit-library -emit-module -module-name NagramSettings \
  Nagram/Settings/NagramSTTConfiguration.swift \
  Nagram/Transcription/Tests/ConfigurationTests.swift \
  -o /tmp/nagram-stt-tests/libNagramSettings.dylib \
  -emit-module-path /tmp/nagram-stt-tests/NagramSettings.swiftmodule
```

`STT_LIBRARY` 仅排除配置测试的 `@main` 入口；不修改或剥离生产配置源码。

编译实际 provider 与测试入口，然后运行 mock：

```sh
xcrun swiftc -swift-version 5 \
  -module-cache-path /tmp/nagram-stt-tests/cache \
  -I /tmp/nagram-stt-tests -L /tmp/nagram-stt-tests \
  -lSwiftSignalKit -lNagramSettings \
  -Xlinker -rpath -Xlinker /tmp/nagram-stt-tests \
  Nagram/Transcription/Sources/NagramOpenAITranscriptionProvider.swift \
  Nagram/Transcription/Tests/ProviderTests.swift \
  -o /tmp/nagram-stt-tests/provider

python3 Nagram/Transcription/Tests/provider_mock.py \
  /tmp/nagram-stt-tests/provider \
  Nagram/Transcription/Resources/NagramSTTTest.m4a
```

mock 仅绑定 `127.0.0.1` 的系统分配端口，传入的 `fictional-test-key` 是固定测试字符串，不是真实凭据。Python 会启动测试二进制，并在结束时停止 HTTP server；退出码非零表示失败。

预期输出：

```text
PASS: multipart bytes, fields, model language compatibility, JSON, 429/redaction, empty result, malformed response, redirect rejection, size validation, cancellation and cleanup.
```

具体断言包括：

- 音频字节与 fixture 一致，文件名 `audio.m4a`，MIME 为 `audio/mp4`。
- `model`、`response_format=json`、提示词按要求编码；指定 `gpt-transcribe` 语言发送 `languages[]`，自动语言不发送语言字段。
- 成功响应解析和首尾空白清理。
- HTTP 429 保留错误状态且去除回显的测试 key。
- 空文字返回 `noSpeech`，缺少正确字段返回 `invalidResponse`。
- HTTP 302 不跟随跳转。
- 空音频和超出 25,000,000 字节的音频在上传前拒绝。
- 取消慢请求后不交付结果，且清理该请求的 multipart 临时目录。

## 外部 API 与真机验证边界

2026-09-08 已使用生产 provider 对 OpenAI 官方 `gpt-4o-mini-transcribe` 发起一次实际请求，约 3.27 秒返回 `This is a speech recognition test.`。该验证使用无回显输入提供真实凭据；凭据和读取凭据的临时 harness 不纳入仓库。

需要重做真实 API 验证时，可在 Nagram 的“自定义 STT API”页配置自己的服务后点击“测试转写”。它使用同一内置音频与生产 provider，请求可能收费。

真机签名构建、安装、设置页和官方样例转写的验收结果，以及尚未覆盖的聊天场景，记录在 [功能说明](../../../docs/custom-stt.md)。这些独立测试本身不覆盖 iPhone 的媒体解码、数据库或 UI 行为。
