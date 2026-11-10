# 自定义语音转文字（STT）

Nagram 可以把聊天中的语音消息和圆视频音轨交给自定义 OpenAI-compatible Transcriptions API 识别，并在原有消息气泡中显示文字。此功能处理用户主动选择的消息，不会自动上传聊天内容。

## 设置入口

打开 **设置 → Nagram 设置 → 消息 → 语音转文字**。该分组位于“翻译”分组之后。

- **识别方式 → 默认**：保留 Telegram 现有选择逻辑与会员、试用、频道加成限制；原有本地识别实验设置仍按原逻辑参与选择。
- **识别方式 → 本机识别（系统）**：使用 iOS 自带的 Apple 语音识别（`SFSpeechRecognizer`），只在设备上识别，免费、无需会员和配置。详见下文“本机识别（系统）”。
- **识别方式 → 自定义（OpenAI 兼容）**：使用下方配置的外部 API。服务商的费用和配额与 Telegram 转写额度独立。
- **本机识别语言**：只对本机识别生效，见下文。
- **自定义 STT API**：进入配置页。

切换识别方式不会自动重新上传消息。已有识别文本继续显示；需要替换时，长按消息选择“重新识别”，使用当前选择的识别方式重新请求。

## 本机识别（系统）

选中“本机识别（系统）”后，与自定义方式一样，非会员也显示转文字按钮，不受 Telegram 会员、试用次数和冷却限制。识别在 `Nagram/Transcription/Sources/NagramSystemSpeechTranscriptionProvider.swift`，由 `NagramTranscriptionService` 调度。上游 `LocalAudioTranscription`（调试菜单的实验开关）把权限被拒、语言不支持等情况一律当作“无结果”，并在没有本机模型时允许交给 Apple 服务器，所以这里另写了 provider；上游实验开关仍只在“默认”方式下按原逻辑生效。

| 项目 | 行为 |
| --- | --- |
| 权限 | 首次点击转文字时请求“语音识别”权限（`NSSpeechRecognitionUsageDescription`，en/ja/zh-hans/zh-hant 有本地化）。被拒绝时提示到 iOS 设置中为 Nagram 开启“语音识别”；被屏幕使用时间等限制时单独提示。权限与语言检查在标记 pending 和下载音频之前完成。 |
| 语言 | “本机识别语言”：自动（按系统首选语言顺序取第一个 Apple 支持的语言）、跟随应用语言，或指定普通话（中国大陆/台湾）、粤语（香港）、英语、日语、韩语。中文按书写体系选择：简体对应 `zh-CN`，繁体对应 `zh-TW`，地区为香港/澳门时优先 `zh-HK`（粤语）。 |
| 只用本机模型 | 请求固定 `requiresOnDeviceRecognition = true`。语言不受支持、该语言没有本机模型（`supportsOnDeviceRecognition == false`）或识别器不可用时直接报错，不回退到 Apple 服务器或其他方式。本机模型随系统听写下载：iOS 设置 → 通用 → 键盘 → 开启听写，并添加对应语言。 |
| 音频 | 与自定义方式共用 `nagramPrepareTranscriptionAudio`：圆视频只取音轨，转成单声道 AAC 临时文件后交给识别器；结束或取消后删除临时文件。 |
| 时长 | 只接受 5 分钟以内的消息，超出时提示，不截断；整个任务 10 分钟超时。 |
| 取消和重试 | 与自定义方式相同：长按“取消识别”、进入后台或账号移除都会取消识别任务（`SFSpeechRecognitionTask.cancel()`）；失败后可点击重试或“重新识别”。 |
| 结果 | 写入同一个 `AudioTranscriptionMessageAttribute`，来源为 `local`，带请求 ID；不发送 Telegram 评分 RPC。“重新识别”使用当前选中的方式。 |
| 范围 | 与自定义方式相同，仅普通云消息中的语音和圆视频；秘密聊天、一次性媒体和预览除外。 |

验证记录（**2026-11-10**）：`debug_sim_arm64` 全量构建通过；iPhone 18 Pro Max 模拟器上确认“识别方式”出现三项、“本机识别语言”行和新页脚，选中本机识别后偏好写入 `systemSpeech`，构建产物的 `Info.plist` 与 `zh-hans.lproj/InfoPlist.strings` 含语音识别用途说明。模拟器账号中没有语音消息，权限请求、识别结果和拒绝提示**未在模拟器上验证**。

真机验证步骤：在 iOS 设置 → 通用 → 键盘中开启听写并添加中文；Nagram 中选择本机识别；点开一条语音消息的转文字按钮，确认首次弹出语音识别权限请求、授权后出现文字，长按可“重新识别”；再到 iOS 设置中关闭 Nagram 的语音识别权限，确认点击后出现开启权限的提示；把“本机识别语言”改为未下载听写模型的语言，确认提示没有本机识别模型。

## 配置项

| 配置项 | 行为 |
| --- | --- |
| Base URL | 留空使用 `https://api.openai.com`。支持兼容服务的域名、端口和代理路径。 |
| Endpoint | 留空使用 `/v1/audio/transcriptions`；可以填写路径或完整 HTTP/HTTPS URL。完整 URL 优先于 Base URL。 |
| API Key | OpenAI 官方地址必填；允许不需要鉴权的自定义服务留空。非空时发送 Bearer 鉴权。 |
| 模型 | 必填。填写该服务实际支持的转写模型，例如 OpenAI 的 `gpt-4o-mini-transcribe`。界面的占位文字不会自动保存为模型。 |
| 识别语言 | 留空自动识别；指定时填写 `zh`、`en`、`ja` 等两字母语言代码。首尾空白移除，大写转小写。 |
| 识别提示词 | 可选的人名、专有名词等提示。留空不发送。是否支持由所选模型决定。 |
| 测试转写 | 将内置短音频经 `nagramPrepareTranscriptionAudio` 的 FFmpeg 解码和 AAC 转码后交给生产 provider；临时音频持有到上传结束或取消。不使用聊天音频，请求可能产生费用。真机已验证内置音频成功转写，以及 HTTP 401 错误反馈。 |

设置修改后自动保存。API Key 使用独立的本机 Keychain 项，采用 `AfterFirstUnlockThisDeviceOnly`，不与翻译 API Key 共用，不通过 iCloud 同步。其余 STT 设置按 Nagram 现有设置同步开关和白名单同步。

Keychain 读写失败会显示错误。写入失败时，配置页保留尚未保存的输入；再次点击测试会先重试保存，仍失败则不发送请求。测试过程中点击“取消测试”可取消本次上传；离开配置页也会释放该测试请求。

### URL 拼接示例

| Base URL | Endpoint | 最终 URL |
| --- | --- | --- |
| 空 | 空 | `https://api.openai.com/v1/audio/transcriptions` |
| `https://example.test/v1` | 空 | `https://example.test/v1/audio/transcriptions` |
| `https://example.test/proxy/v1/` | 空 | `https://example.test/proxy/v1/audio/transcriptions` |
| `https://example.test/proxy` | `custom/transcribe` | `https://example.test/proxy/custom/transcribe` |
| 任意 | `https://gateway.test/transcribe?tenant=sample` | 完整 Endpoint 原样决定目标地址，并保留查询参数。 |
| `http://localhost:8080` | 空 | `http://localhost:8080/v1/audio/transcriptions` |

拼接会清理 Base URL 尾部斜杠，避免 `/v1/v1` 重复。URL 中不能嵌入用户名或密码；OpenAI 官方地址必须使用 HTTPS。HTTP 本地服务在 iPhone 上的实际连通性还取决于服务监听地址、系统网络策略和本地网络权限；`localhost` 指向运行 Nagram 的设备本身。

## 识别链路与当前范围

聊天语音或圆视频 → 获取完整媒体资源 → 软件解码音轨 → AAC/M4A 临时文件 → multipart 上传 → 解析 JSON `text` → 条件写回消息转写属性 → 更新气泡。

当前实现采用非流式请求，等待完整文本后显示结果。聊天媒体转换为单声道、48 kHz、32 kbit/s AAC，圆视频只上传提取后的音轨。转换后的音频文件上限为 **25,000,000 字节（25 MB）**；超过上限会明确失败，不自动切片。上传体写入临时文件，结束或取消后清理，不删除 MediaBox 中的原消息媒体。

请求使用 `model`、`file`、`response_format=json`，可选发送语言及提示词。语言自动时完全省略语言字段；`gpt-transcribe` 使用 `languages[]`，其他模型使用 `language`。首版不提供实时识别、分段流式结果、说话人分离、模型列表拉取或任意自定义 Header。

自定义聊天转写仅处理普通云消息中的语音和圆视频；排除秘密聊天、阅后即焚的一次性媒体、预览，以及尚未成为云消息的内容。输入框听写、通话实时字幕和自动批量转写不在此功能范围内。

## 任务生命周期、取消和重试

同一账号的同一消息共享一个进行中任务，重复点击不会重复上传。消息 cell 离屏只取消自身观察，不持有整个上传任务的生命周期，因此滚出再滚回不会单独重启请求。

聊天转写进行中，长按消息可选择“取消识别”。应用进入后台，或任务所属账号被退出/移除时，也会取消该聊天任务。返回前台后不会自动续传，用户可以点击重试或使用“重新识别”。服务端已经接收请求后，客户端取消不保证服务商免除该次费用。

失败会结束 pending 状态并提供可重试的错误反馈；网络、配额和响应错误不会自动切换到其他服务商。下载、音频转换、上传和整个任务都有边界检查或超时约束，避免任务一直保持进行中。

## 结果来源与兼容性

转写结果继续使用 `AudioTranscriptionMessageAttribute`，并记录来源和请求 ID。旧属性默认按 legacy 解码，兼容已有数据库。自定义结果属于 external，本地识别结果属于 local；只有可对应真实 Telegram 转写 ID 的 Telegram/legacy 结果才允许发送 Telegram 评分 RPC。

写回时检查当前请求 ID 和来源，防止旧请求完成、Telegram 后续推送或其他来源的结果覆盖新请求。重新识别会清理与旧文本绑定的翻译状态；翻译回写也检查其对应的原始转写，避免旧译文覆盖新识别文本。完成后的识别文本可沿 Nagram 现有翻译功能继续翻译。

关闭自定义方式后，新请求恢复默认路线。已有外部结果不会因为关闭开关自动删除；用户明确选择“重新识别”后，才由当前方式替换。

## 验证记录

以下结果记录于 **2026-09-08**，并区分命令行/provider 验证与 iPhone 完整链路验证。

| 验证 | 结果 | 能证明的范围 |
| --- | --- | --- |
| `ConfigurationTests.swift` | **55 assertions 通过** | 编译真实配置源码；验证 URL、字段、校验、不可变快照和 credential 读取错误。仅 Settings/Keychain 使用内存桩。 |
| 生产 provider + 本地 HTTP mock | **通过** | 实际 multipart 文件字节、字段、模型语言兼容、JSON 文本、429/密钥脱敏、空结果、错误响应、拒绝重定向、大小检查、取消与临时目录清理。 |
| OpenAI 官方生产 provider 请求 | **通过** | 独立命令行使用实际生产 provider、配置构造器及 SwiftSignalKit，直接上传 fixture；模型 `gpt-4o-mini-transcribe`，一次请求约 **3.27 秒**，返回 `This is a speech recognition test.`。该结果未覆盖随后加入测试按钮的 FFmpeg 解码与 AAC 转码路径。 |
| Swift 源码语法检查、四语言 strings lint、diff 空白检查 | **通过** | 语法和文件格式的静态检查。 |
| 真机应用构建 | **通过** | `debug_arm64`，Xcode 27 版本 override，主应用及 6 个扩展共 7 份 profile 全签名。最终构建耗时 **53.142 秒**；此前一次完整应用构建耗时 **464.222 秒**，也成功。 |
| IPA 签名检查与真机安装 | **通过** | `codesign --verify --deep --strict` 通过；通过 Wi-Fi 使用 `devicectl` 安装至 iPhone 16 Pro Max / iOS 27，安装后查询版本为 **12.9.3 (1)**。 |
| 真机 Demo 配置页 | **通过** | 6 个输入字段可见，标签与输入内容的 8 pt 间距已复测；模型缺失和 API Key 缺失提示正确，模型及独立 Keychain 凭据在重启后保留。 |
| 真机内置测试音频的失败路径 | **通过** | 使用错误凭据触发 OpenAI HTTP 401，错误正确呈现；证明已通过音频准备、上传及 HTTP 错误反馈链路，不证明成功识别或音频识别质量。 |
| 真机内置音频成功转写 | **通过** | 在最终安装的 build 1、iPhone 16 Pro Max / iOS 27 Demo 配置页纠正凭据后点击“Test Transcription”，操作行先显示“Cancel Test”，随后弹出“Transcription Test Succeeded”，结果严格为 `This is a speech recognition test.`。覆盖内置音频准备、上传、官方识别和成功 UI。 |
| 真机 provider 切换与测试凭据清理 | **通过** | `default → custom → default` 的菜单及行内容即时更新；重新进入 API 页后模型和 Key 保留。清空 Demo API Key 后再次测试，正确提示 `api.openai.com` 缺少 Key，确认 Demo credential 已删除。随后不带 `--demo` 重新启动，并通过手机镜像确认已恢复日常模式的中文 STT 设置页。 |
| 真实聊天语音与圆视频 | **通过（用户确认）** | 2026-09-08，用户在真机安装版本上确认语音消息和圆视频转写测试通过。该结果来自用户实测反馈，未记录具体样本、时长或音频编码。 |
| 生命周期与并发测试 | **未专项验证** | 后台取消，以及评分和转写/译文回写竞态尚未进行专门的运行验证。 |


音频 reader 当前调整仅排空已解码的队列，不等于完成 codec 与 swresample 的完整 flush。常规语音与圆视频转写已实测确认；非常规音频编码、时间戳、逐样本尾部完整性，以及后台取消、评分和转写/译文竞态仍未专项验证。

离线配置测试与本地 mock 的复现步骤见 [STT 测试说明](../Nagram/Transcription/Tests/README.md)。API 参数参考 [OpenAI Create transcription](https://developers.openai.com/api/reference/resources/audio/subresources/transcriptions/methods/create/index.md)。

## 主要实现位置

- `Nagram/Settings/NagramSTTConfiguration.swift`、`NagramSTTKeychain.swift`：配置和本机凭据。
- `Nagram/SettingsUI/NagramSTTSettingsController.swift`：自定义 API 页面。
- `Nagram/Transcription/Sources/`：共享任务、音轨准备、multipart provider。
- `submodules/TelegramCore/Sources/SyncCore/SyncCore_AudioTranscriptionMessageAttribute.swift`：来源、请求 ID 与兼容解码。
- `submodules/TelegramCore/Sources/TelegramEngine/Messages/`：转写属性条件写回和评分入口。
- 文件消息与圆视频组件：原气泡转写入口、结果状态及设置变化刷新。
