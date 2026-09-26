# 发送前翻译输入内容(NAG-75)实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 长按发送按钮菜单新增「翻译」项,用 Nagram 已配置的翻译 provider 把输入框全文翻译为全局设置的目标语言并替换输入框内容(保留 entities),默认关闭。

**Architecture:** 三层改动——(1) `Nagram/Settings` + `Nagram/SettingsUI` + `Nagram/Strings` 加开关与目标语言设置;(2) `ChatSendMessageActionUI` 的 `SendMessage` params 加可选闭包字段 `nagramTranslateInput`,组件菜单在闭包非 nil 时插入「翻译」项(该模块不依赖任何 Nagram 模块,显隐判断在调用方);(3) `TelegramUI` 的 `ChatMessageDisplaySendMessageOptions.swift` 在 `.sendMessage` 分支按条件构造闭包:调 `NagramTranslateService` 翻译,成功后经 `withUpdatedEffectiveInputState` 回填输入框,失败 toast。

**Tech Stack:** Swift、SwiftSignalKit(Signal)、Bazel(Make.py)、jj(版本管理)。

Spec: `docs/superpowers/specs/2026-07-26-translate-before-send-design.md`

## Global Constraints

- 版本管理只用 **jj**,禁止任何 `git` 命令(含只读);提交用 `jj commit -m "<type>: <summary>"`。
- `submodules/` 下每处上游文件修改必须有邻近的 `// MARK: NAGRAM` 注释;`Nagram/` 目录内是 Nagram 自有代码,不需要。
- `submodules/ChatSendMessageActionUI` **不得**新增对任何 Nagram 模块(NagramSettings / NagramStrings / NagramTranslate)的依赖;菜单项文案复用上游 `environment.strings.Conversation_ContextMenuTranslate`。
- 不改 `TelegramCore`、不加新 Nagram 模块、不加新 engine wrapper。
- 项目无覆盖此路径的单元测试;每个任务的验证 = 全量模拟器构建(命令见各任务,预期 exit 0 且输出含 `Build completed successfully`)。
- 四个语言文件(`en` / `ja` / `zh-hans` / `zh-hant` 的 `NagramLocalizable.strings`)的 key 集合必须保持一致。
- 删除文件用 `trash`,不用 `rm -rf`(本计划无删除需求,仅备忘)。

构建命令(所有任务共用,下文简称「全量构建」):

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-system/appstore-configuration.json \
  --xcodeManagedCodesigning --buildNumber=1 \
  --configuration=debug_sim_arm64 --continueOnError
```

---

### Task 1: 设置项 + 设置界面 + 多语言字符串

**Files:**
- Modify: `Nagram/Settings/NagramSettings.swift`(约 411 行,`translationLLMTemperatureTenths` 之后)
- Modify: `Nagram/SettingsUI/NagramSettingsController.swift`(约 435–438 行,Translation 分组)
- Modify: `Nagram/Strings/Strings/en.lproj/NagramLocalizable.strings`
- Modify: `Nagram/Strings/Strings/ja.lproj/NagramLocalizable.strings`
- Modify: `Nagram/Strings/Strings/zh-hans.lproj/NagramLocalizable.strings`
- Modify: `Nagram/Strings/Strings/zh-hant.lproj/NagramLocalizable.strings`

**Interfaces:**
- Consumes: `@NagramDefault` 属性包装器、`NagramGroup`/`NagramRow`(`.toggle` / `.choice`)现有机制。
- Produces(Task 3 依赖):
  - `NagramSettings.shared.translateBeforeSend: Bool`(key `nagram.translateBeforeSend`,默认 `false`)
  - `NagramSettings.shared.translateBeforeSendTargetLang: String`(key `nagram.translateBeforeSendTargetLang`,默认 `"en"`)
  - 字符串 key `Nagram.TranslateBeforeSend.Failed`(失败 toast 用)

- [ ] **Step 1: 确认 jj 状态**

```sh
jj st && jj log -r @ -n 1
```

预期:`@` 为空(no changes)。若 `@` 非空且与本任务无关,按 VCS Policy 先 `jj desc -m "wip: <inferred topic>"` 处理后再继续。

- [ ] **Step 2: 在 `NagramSettings.swift` 添加两个设置项**

位置:`translationLLMTemperatureTenths` 属性(约 409–411 行)之后、`// MARK: 波次 3 批 D` 之前:

```swift
    /// 发送前翻译:长按发送按钮菜单显示「翻译」项,译文回填输入框(NAG-75)。
    @NagramDefault("nagram.translateBeforeSend", false)
    public var translateBeforeSend: Bool
    /// 发送前翻译的目标语言代码(popularTranslationLanguages 短列表)。
    @NagramDefault("nagram.translateBeforeSendTargetLang", "en")
    public var translateBeforeSendTargetLang: String
```

- [ ] **Step 3: 在 `NagramSettingsController.swift` 的 Translation 分组追加两行**

找到 Translation 分组(约 435–438 行),在 `.navigation(titleKey: "Nagram.TranslationLLMSettings", ...)` 行之后追加:

```swift
            .toggle(titleKey: "Nagram.TranslateBeforeSend", get: { NagramSettings.shared.translateBeforeSend }, set: { NagramSettings.shared.translateBeforeSend = $0 }),
            .choice(titleKey: "Nagram.TranslateBeforeSendTargetLang", prefix: "Nagram.TranslateBeforeSendTargetLang", options: ["en", "ar", "zh", "fr", "de", "it", "ja", "ko", "pt-BR", "ru", "es", "uk"], current: { NagramSettings.shared.translateBeforeSendTargetLang }, set: { NagramSettings.shared.translateBeforeSendTargetLang = $0 }),
```

说明:12 个语言代码就是 `TranslateUI` 里 `popularTranslationLanguages` 的字面值;不 import `TranslateUI`(避免设置模块拖入大依赖),直接写字面量。

- [ ] **Step 4: 四个 strings 文件各追加同一组 key**

每个文件都在 `"Nagram.TranslationProvider.transmart" = ...;` 行之后插入(四个文件行布局一致,约 319 行)。

`en.lproj/NagramLocalizable.strings`:

```
"Nagram.TranslateBeforeSend" = "Translate Before Send";
"Nagram.TranslateBeforeSend.Failed" = "Translation failed";
"Nagram.TranslateBeforeSendTargetLang" = "Translate To";
"Nagram.TranslateBeforeSendTargetLang.en" = "English";
"Nagram.TranslateBeforeSendTargetLang.ar" = "Arabic";
"Nagram.TranslateBeforeSendTargetLang.zh" = "Chinese";
"Nagram.TranslateBeforeSendTargetLang.fr" = "French";
"Nagram.TranslateBeforeSendTargetLang.de" = "German";
"Nagram.TranslateBeforeSendTargetLang.it" = "Italian";
"Nagram.TranslateBeforeSendTargetLang.ja" = "Japanese";
"Nagram.TranslateBeforeSendTargetLang.ko" = "Korean";
"Nagram.TranslateBeforeSendTargetLang.pt-BR" = "Portuguese (Brazil)";
"Nagram.TranslateBeforeSendTargetLang.ru" = "Russian";
"Nagram.TranslateBeforeSendTargetLang.es" = "Spanish";
"Nagram.TranslateBeforeSendTargetLang.uk" = "Ukrainian";
```

`zh-hans.lproj/NagramLocalizable.strings`:

```
"Nagram.TranslateBeforeSend" = "发送前翻译";
"Nagram.TranslateBeforeSend.Failed" = "翻译失败";
"Nagram.TranslateBeforeSendTargetLang" = "翻译目标语言";
"Nagram.TranslateBeforeSendTargetLang.en" = "英语";
"Nagram.TranslateBeforeSendTargetLang.ar" = "阿拉伯语";
"Nagram.TranslateBeforeSendTargetLang.zh" = "中文";
"Nagram.TranslateBeforeSendTargetLang.fr" = "法语";
"Nagram.TranslateBeforeSendTargetLang.de" = "德语";
"Nagram.TranslateBeforeSendTargetLang.it" = "意大利语";
"Nagram.TranslateBeforeSendTargetLang.ja" = "日语";
"Nagram.TranslateBeforeSendTargetLang.ko" = "韩语";
"Nagram.TranslateBeforeSendTargetLang.pt-BR" = "葡萄牙语（巴西）";
"Nagram.TranslateBeforeSendTargetLang.ru" = "俄语";
"Nagram.TranslateBeforeSendTargetLang.es" = "西班牙语";
"Nagram.TranslateBeforeSendTargetLang.uk" = "乌克兰语";
```

`zh-hant.lproj/NagramLocalizable.strings`:

```
"Nagram.TranslateBeforeSend" = "傳送前翻譯";
"Nagram.TranslateBeforeSend.Failed" = "翻譯失敗";
"Nagram.TranslateBeforeSendTargetLang" = "翻譯目標語言";
"Nagram.TranslateBeforeSendTargetLang.en" = "英語";
"Nagram.TranslateBeforeSendTargetLang.ar" = "阿拉伯語";
"Nagram.TranslateBeforeSendTargetLang.zh" = "中文";
"Nagram.TranslateBeforeSendTargetLang.fr" = "法語";
"Nagram.TranslateBeforeSendTargetLang.de" = "德語";
"Nagram.TranslateBeforeSendTargetLang.it" = "義大利語";
"Nagram.TranslateBeforeSendTargetLang.ja" = "日語";
"Nagram.TranslateBeforeSendTargetLang.ko" = "韓語";
"Nagram.TranslateBeforeSendTargetLang.pt-BR" = "葡萄牙語（巴西）";
"Nagram.TranslateBeforeSendTargetLang.ru" = "俄語";
"Nagram.TranslateBeforeSendTargetLang.es" = "西班牙語";
"Nagram.TranslateBeforeSendTargetLang.uk" = "烏克蘭語";
```

`ja.lproj/NagramLocalizable.strings`:

```
"Nagram.TranslateBeforeSend" = "送信前に翻訳";
"Nagram.TranslateBeforeSend.Failed" = "翻訳に失敗しました";
"Nagram.TranslateBeforeSendTargetLang" = "翻訳先の言語";
"Nagram.TranslateBeforeSendTargetLang.en" = "英語";
"Nagram.TranslateBeforeSendTargetLang.ar" = "アラビア語";
"Nagram.TranslateBeforeSendTargetLang.zh" = "中国語";
"Nagram.TranslateBeforeSendTargetLang.fr" = "フランス語";
"Nagram.TranslateBeforeSendTargetLang.de" = "ドイツ語";
"Nagram.TranslateBeforeSendTargetLang.it" = "イタリア語";
"Nagram.TranslateBeforeSendTargetLang.ja" = "日本語";
"Nagram.TranslateBeforeSendTargetLang.ko" = "韓国語";
"Nagram.TranslateBeforeSendTargetLang.pt-BR" = "ポルトガル語（ブラジル）";
"Nagram.TranslateBeforeSendTargetLang.ru" = "ロシア語";
"Nagram.TranslateBeforeSendTargetLang.es" = "スペイン語";
"Nagram.TranslateBeforeSendTargetLang.uk" = "ウクライナ語";
```

- [ ] **Step 5: 校验四个文件 key 数量一致**

```sh
for f in Nagram/Strings/Strings/*.lproj/NagramLocalizable.strings; do echo "$f: $(grep -c 'Nagram.TranslateBeforeSend' $f)"; done
```

预期:四个文件都输出 `15`(1 开关 + 1 失败 + 1 标题 + 12 语言,每行都含 `Nagram.TranslateBeforeSend` 前缀)。

- [ ] **Step 6: 全量构建**

运行 Global Constraints 中的构建命令。预期 exit 0,输出含 `Build completed successfully`。

- [ ] **Step 7: 提交**

```sh
jj commit -m "feat: add translate-before-send settings and target language (NAG-75)"
```

---

### Task 2: 发送选项菜单可选「翻译」项(ChatSendMessageActionUI)

**Files:**
- Modify: `submodules/ChatSendMessageActionUI/Sources/ChatSendMessageActionSheetController.swift`(`SendMessage` 类,15–56 行)
- Modify: `submodules/ChatSendMessageActionUI/Sources/ChatSendMessageContextScreen.swift`(菜单构建 `.sendMessage` 分支,约 554–557 行)

**Interfaces:**
- Consumes: 无(本任务自包含;不得 import 任何 Nagram 模块)。
- Produces(Task 3 依赖): `SendMessageActionSheetControllerParams.SendMessage` 新增存储属性与 init 参数 `nagramTranslateInput: (() -> Void)? = nil`。组件通过 `component.params` 直接读取,`makeChatSendMessageActionSheetController` 与 `ChatSendMessageContextScreen.init` **无需改动**(params 整体透传)。

- [ ] **Step 1: `SendMessage` 类加字段与 init 参数**

在 `ChatSendMessageActionSheetController.swift` 中,`public let isMonoforum: Bool`(27 行)之后加:

```swift
        // MARK: NAGRAM — 发送前翻译输入内容(NAG-75):非 nil 时菜单显示「翻译」项
        public let nagramTranslateInput: (() -> Void)?
```

init 签名 `isMonoforum: Bool`(41 行)之后加(带默认值,现有调用点无需改动):

```swift
            isMonoforum: Bool,
            nagramTranslateInput: (() -> Void)? = nil
```

init 体 `self.isMonoforum = isMonoforum`(54 行)之后加:

```swift
            self.nagramTranslateInput = nagramTranslateInput
```

- [ ] **Step 2: 菜单构建处插入「翻译」项**

在 `ChatSendMessageContextScreen.swift` 中找到(约 554 行):

```swift
            switch component.params {
            case let.sendMessage(sendMessage):
                if !reminders {
```

在 `case let.sendMessage(sendMessage):` 与 `if !reminders {` 之间插入(位于「静音发送」之前,且不受 reminders 限制——Saved Messages 里也可用):

```swift
                // MARK: NAGRAM — 发送前翻译输入内容(NAG-75)
                if let nagramTranslateInput = sendMessage.nagramTranslateInput {
                    items.append(.action(ContextMenuActionItem(
                        id: AnyHashable("nagramTranslateInput"),
                        text: environment.strings.Conversation_ContextMenuTranslate,
                        icon: { theme in
                            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Translate"), color: theme.contextMenu.primaryColor)
                        }, action: { [weak self] _, _ in
                            guard let self else {
                                return
                            }
                            self.environment?.controller()?.dismiss()
                            nagramTranslateInput()
                        }
                    )))
                }
```

说明:不设置 `self.animateOutToEmpty = true`(那是发送类动作的消失动画标记;本动作不发送,普通 dismiss 回到输入框)。文案与图标均复用上游资源(`Conversation_ContextMenuTranslate` = "Translate"/"翻译",`Chat/Context Menu/Translate` 是消息菜单翻译项同款图标),模块零新增依赖。

- [ ] **Step 3: 全量构建**

运行 Global Constraints 中的构建命令。预期 exit 0,输出含 `Build completed successfully`。此时菜单项不会出现(所有调用方都还没传 `nagramTranslateInput`,默认 nil),行为无变化。

- [ ] **Step 4: 提交**

```sh
jj commit -m "feat: add optional translate item to send options menu (NAG-75)"
```

---

### Task 3: 触发闭包接线(TelegramUI)+ BUILD 依赖

**Files:**
- Modify: `submodules/TelegramUI/Sources/Chat/ChatMessageDisplaySendMessageOptions.swift`(imports;`.sendMessage` 分支,约 213–255 行)
- Modify: `submodules/TelegramUI/BUILD`(Nagram deps 块,约 76 行)

**Interfaces:**
- Consumes:
  - Task 1: `NagramSettings.shared.translateBeforeSend`、`NagramSettings.shared.translateBeforeSendTargetLang`、字符串 key `Nagram.TranslateBeforeSend.Failed`
  - Task 2: `SendMessageActionSheetControllerParams.SendMessage(... isMonoforum:nagramTranslateInput:)`
  - 既有 API:`NagramTranslateService(context:).translate(text:toLang:entities:)` → `Signal<(String, [MessageTextEntity])?, TranslationError>`(不传 `messageId`,LLM 自动走无上下文分支);`generateChatInputTextEntities(_:)`、`chatInputStateStringWithAppliedEntities(_:entities:)`(TextFormat);`ChatTextInputState(inputText:)`(光标置末尾);`OverlayStatusController`;`controllerInteraction.displayUndo(.info(...))`(UndoUI);`ngI18n(_:_:)`(NagramStrings)
- Produces: 完整功能。

- [ ] **Step 1: `submodules/TelegramUI/BUILD` 加依赖**

Nagram deps 块中 `"//Nagram/SettingsUI:NagramSettingsUI",`(76 行)之后加:

```python
        "//Nagram/Translate:NagramTranslate",
```

(`TranslateUI`、`TextProcessingScreen` 已有同样依赖,无循环。)

- [ ] **Step 2: `ChatMessageDisplaySendMessageOptions.swift` 加 imports**

现有 import 块(1–14 行)末尾追加:

```swift
import TextFormat
import OverlayStatusController
import UndoUI
// MARK: NAGRAM
import NagramSettings
import NagramStrings
import NagramTranslate
```

- [ ] **Step 3: `.sendMessage` 分支构造闭包**

在 `else` 分支(非编辑消息)内、`let controller = makeChatSendMessageActionSheetController(`(约 228 行)之前插入:

```swift
            // MARK: NAGRAM — 发送前翻译输入内容(NAG-75):开关开启、输入非空且 entity-expressible 时提供翻译回填闭包
            var nagramTranslateInput: (() -> Void)?
            if NagramSettings.shared.translateBeforeSend {
                let composeInputState = selfController.presentationInterfaceState.interfaceState.composeInputState
                if !composeInputState.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, composeInputState.content.isEntityExpressible(options: [.quotesRequireRichContent]) {
                    nagramTranslateInput = { [weak selfController] in
                        guard let selfController else {
                            return
                        }
                        let inputText = selfController.presentationInterfaceState.interfaceState.composeInputState.inputText
                        let entities = generateChatInputTextEntities(inputText)
                        let statusController = OverlayStatusController(theme: selfController.presentationData.theme, type: .loading(cancelled: nil))
                        selfController.present(statusController, in: .window(.root))
                        let presentTranslationFailed: (ChatControllerImpl) -> Void = { selfController in
                            selfController.controllerInteraction?.displayUndo(.info(title: nil, text: ngI18n("Nagram.TranslateBeforeSend.Failed", selfController.presentationData.strings.baseLanguageCode), timeout: nil, customUndoText: nil))
                        }
                        let _ = (NagramTranslateService(context: selfController.context).translate(
                            text: inputText.string,
                            toLang: NagramSettings.shared.translateBeforeSendTargetLang,
                            entities: entities
                        )
                        |> deliverOnMainQueue).startStandalone(next: { [weak selfController, weak statusController] result in
                            statusController?.dismiss()
                            guard let selfController else {
                                return
                            }
                            guard let (translatedText, translatedEntities) = result else {
                                presentTranslationFailed(selfController)
                                return
                            }
                            selfController.updateChatPresentationInterfaceState(animated: true, interactive: true, { state in
                                return state.updatedInterfaceState { interfaceState in
                                    return interfaceState.withUpdatedEffectiveInputState(ChatTextInputState(inputText: chatInputStateStringWithAppliedEntities(translatedText, entities: translatedEntities)))
                                }
                            })
                        }, error: { [weak selfController, weak statusController] _ in
                            statusController?.dismiss()
                            guard let selfController else {
                                return
                            }
                            presentTranslationFailed(selfController)
                        })
                    }
                }
            }
```

要点:显隐条件(开关 / 非空 / entity-expressible)在菜单弹出时判定一次;闭包执行时从 `presentationInterfaceState` 重新读取当前文本(菜单打开期间文本不可编辑,一致)。翻译服务返回 `nil` 与 `error` 都走失败 toast,原文不动。

- [ ] **Step 4: params 传入闭包**

同文件 `.sendMessage` params 构造处(约 233–255 行),`isMonoforum: ...` 行之后加:

```swift
                    isMonoforum: selfController.presentationInterfaceState.renderedPeer?.peer?.isMonoForum ?? false,
                    nagramTranslateInput: nagramTranslateInput
```

(即在现有 `isMonoforum:` 实参后补 `nagramTranslateInput: nagramTranslateInput`,注意逗号。)

- [ ] **Step 5: 全量构建**

运行 Global Constraints 中的构建命令。预期 exit 0,输出含 `Build completed successfully`。

- [ ] **Step 6: 提交**

```sh
jj commit -m "feat: wire translate-before-send into send options menu (NAG-75)"
```

---

### Task 4: 收尾验证

**Files:** 无新改动。

- [ ] **Step 1: 确认版本状态**

```sh
jj st && jj log -n 5
```

预期:`@` 为空;其上依次是 Task 3、Task 2、Task 1 的三个 feat 提交与已有的 docs spec 提交。

- [ ] **Step 2: 上游改动标记自查**

```sh
rg -n "nagramTranslateInput" submodules/ | rg -v "MARK: NAGRAM"
```

预期:输出的每一处都能在其上下 3 行内找到 `// MARK: NAGRAM`(用 `rg -n -C 3 "nagramTranslateInput" submodules/` 复核)。

- [ ] **Step 3: 手工验证清单(需模拟器运行,供用户执行)**

1. 设置默认态:Nagram 设置 ▸ 聊天 ▸ 翻译分区出现「发送前翻译」(默认关)与「翻译目标语言」(默认 English)。
2. 开关关闭 / 输入为空 / 富文本内容(如表格、标题)时,长按发送按钮菜单不显示「翻译」项。
3. 开启开关、输入含粗体的纯文本,点「翻译」:loading 出现,译文替换输入框,粗体保留,未自动发送。
4. 断网点「翻译」:toast「翻译失败」,原文不动。
5. 编辑消息分支长按发送按钮:无「翻译」项。
