# 发送前翻译输入内容(NAG-75)设计

Linear issue: https://linear.app/nagram-ios/issue/NAG-75 (标题:发送消息前翻译输入内容)

## 功能概述

长按发送按钮弹出的发送选项菜单(静音发送 / 定时发送所在菜单)新增「翻译」项。点击后,用 Nagram 已配置的翻译提供商(`NagramSettings.translationProvider`,含 Telegram / Google / GoogleCN / Microsoft / Yandex / Transmart / LLM)把输入框全文翻译为全局设置的目标语言,译文替换输入框内容(保留 entities 格式),由用户确认后自行按发送键发出。功能默认关闭,由 Nagram 设置开关控制。

非目标:

- 不做每聊天自动翻译(Android Nagram 式的聊天级开关)。
- 不做原文+译文双语拼接回填。
- 不在输入面板加常驻按钮。
- 不支持编辑消息(edit message)分支与附件(attachment)面板。
- 不支持富文本(非 entity-expressible)内容:表格、标题等结构翻译替换会丢结构,直接不显示菜单项。

## 1. 设置

`Nagram/Settings/NagramSettings.swift` 新增:

```swift
@NagramDefault("nagram.translateBeforeSend", false)
public var translateBeforeSend: Bool

@NagramDefault("nagram.translateBeforeSendTargetLang", "en")
public var translateBeforeSendTargetLang: String
```

`Nagram/SettingsUI/NagramSettingsController.swift` 翻译分区(`Nagram.Section.Translation`)新增两行:

- `.toggle`:「发送前翻译」开关。
- `.choice`:「发送翻译目标语言」,options 取 `popularTranslationLanguages` 短列表(en / ar / zh / fr / de / it / ja / ko / pt-BR / ru / es / uk,12 项),沿用现有 ActionSheet 选择交互。

`Nagram/Strings` 新增键(中英):开关标题、目标语言标题(prefix 形式 `Nagram.TranslateBeforeSendTargetLang.<code>`)及 12 个语言显示名。

## 2. 菜单项(ChatSendMessageActionUI)

该模块不依赖 NagramSettings;显隐判断放在调用方,通过可选闭包传入。改动均带 `// MARK: NAGRAM`:

- `SendMessageActionSheetControllerParams.SendMessage` 增加字段 `nagramTranslateInput: (() -> Void)?`(init 同步增加,默认 `nil`)。
- `makeChatSendMessageActionSheetController` → `ChatSendMessageContextScreen` 透传。
- `ChatSendMessageContextScreen` 菜单构建处(`.sendMessage` 分支):当 `nagramTranslateInput != nil` 时,在「静音发送」项之前插入「翻译」项,图标用 `Chat/Context Menu/Translate`,action 为 dismiss 菜单后调用闭包。

## 3. 触发逻辑(TelegramUI)

`submodules/TelegramUI/Sources/Chat/ChatMessageDisplaySendMessageOptions.swift`(`// MARK: NAGRAM`):

仅在 `.sendMessage` 分支构造闭包,满足以下条件才传非 nil:

1. `NagramSettings.shared.translateBeforeSend == true`;
2. 输入文本非空(`composeInputState.inputText.string` 非空白);
3. 内容 entity-expressible(与 `makeRichTextSendPreview` 同一 `isEntityExpressible` 判定;富文本结构不支持)。

闭包实现(在 `ChatControllerImpl` 上下文中):

1. 读取 `presentationInterfaceState.interfaceState.composeInputState.inputText`,用 `generateChatInputTextEntities` 提取 entities;
2. 显示模态 loading(`OverlayStatusController`);
3. 调 `NagramTranslateService(context:).translate(text:toLang:entities:)`,`toLang` 取 `NagramSettings.shared.translateBeforeSendTargetLang`;
4. 成功:收起 loading,用 `chatInputStateStringWithAppliedEntities(text, entities:)` 构造 `ChatTextInputState`(光标置末尾),经 `updateChatPresentationInterfaceState` 替换 `effectiveInputState`(与现有「翻译选中文本」`presentInputTextTranslation` 回填同一模式);
5. 失败(含返回 nil):收起 loading,toast 提示翻译失败,输入框保持原文。

构建依赖:`submodules/TelegramUI/BUILD` 增加 `//Nagram/Translate:NagramTranslate`(TranslateUI、TextProcessingScreen 已有同样依赖,无循环)。

## 4. 错误与边界

- 翻译失败 / 超时:toast 报错,原文不动,不发送。
- 翻译期间模态 loading 防止误操作,完成或失败即撤。
- LLM 提供商的上下文模式需要 `messageId`;本场景不传 `messageId`,`NagramTranslateService.translateExternally` 现有逻辑自动走无上下文分支,无需改动。
- Telegram 官方提供商经由 `nagramTargetLanguage` 做目标语言映射,现有逻辑复用。
- 菜单项点击后输入内容被替换而非发送,用户可以继续编辑或撤销(重新输入);不自动发送是有意设计(触发方式由用户选定为「翻译后回填输入框」)。

## 5. 验证

- 全量模拟器构建 `debug_sim_arm64`(项目无覆盖此路径的单测)。
- 人工验证:
  - 开关关闭 / 输入为空 / 富文本内容时菜单项不显示;
  - 开启后翻译替换输入框、粗体等 entities 保留;
  - 断网或提供商失败时 toast 且原文不动;
  - 编辑消息分支不出现该菜单项。
