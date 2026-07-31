import Foundation

// MARK: NAGRAM — 增强开关集中地。
// 数据层零 Telegram 依赖，本地 UserDefaults + iCloud KVS 镜像。每个开关一行 @NagramDefault 声明（复用核心）。
// 默认值原则：增强开关默认 = 不改变 Telegram 原生行为（除明确语义需要）。

/// 极简 UserDefaults property wrapper。支持 Bool / Int32 / String（覆盖全部开关类型）。
/// 无缓存：直读直写，配合 nagramBoolSignal 的 didChangeNotification 监听天然一致。
@propertyWrapper
public struct NagramDefault<T> {
    private let key: String
    private let defaultValue: T

    public init(_ key: String, _ defaultValue: T) {
        self.key = key
        self.defaultValue = defaultValue
    }

    public var wrappedValue: T {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: key) != nil else { return defaultValue }
            switch T.self {
            case is Bool.Type:
                return defaults.bool(forKey: key) as! T
            case is Int32.Type:
                return Int32(defaults.integer(forKey: key)) as! T
            case is String.Type:
                return (defaults.string(forKey: key) ?? (defaultValue as! String)) as! T
            default:
                return (defaults.object(forKey: key) as? T) ?? defaultValue
            }
        }
        nonmutating set {
            NagramSettingsCloudSync.shared.set(newValue, forKey: key)
        }
    }
}

public enum NagramChatListSwipeAction: String {
    case both
    case folderSwitch = "switch"
    case quickActions = "quick"
    case none

    public var allowsFolderSwitch: Bool {
        switch self {
        case .both, .folderSwitch:
            return true
        case .quickActions, .none:
            return false
        }
    }

    public var allowsQuickActions: Bool {
        switch self {
        case .both, .quickActions:
            return true
        case .folderSwitch, .none:
            return false
        }
    }
}

public enum NagramChatListStartupFolderMode: String {
    case telegramDefault = "telegram"
    case last
    case specific
}

public enum NagramChatListFolderTabDisplayMode: String {
    case text
    case icon
    case iconAndText = "both"
}

public enum NagramChatListMessagePreviewStyle: String {
    case three
    case two
}

public enum NagramGlassTransparencyMode: String {
    case system
    case custom
}

public enum NagramGroupProfileSettingItem: String, CaseIterable, Hashable {
    case groupType
    case inviteLinks
    case linkedChannel
    case reactions
    case appearance
    case history
    case topics
    case location
    case members
    case permissions
    case admins
    case memberRequests
    case removedUsers
    case recentActions
    case community
    case deleteGroup
    case other
}

public enum NagramTranslationProvider: String, CaseIterable {
    case telegram
    case google
    case googleCN = "google-cn"
    case microsoft
    case yandex
    case transmart
    case llm
}

public enum NagramTranslationLLMAPIFormat: String, CaseIterable {
    case openai
    case anthropic

    public var defaultBaseURL: String {
        switch self {
        case .openai:
            return "https://api.openai.com"
        case .anthropic:
            return "https://api.anthropic.com"
        }
    }

    public var defaultTranslationEndpoint: String {
        switch self {
        case .openai:
            return "/v1/chat/completions"
        case .anthropic:
            return "/v1/messages"
        }
    }

    public var defaultModelsEndpoint: String {
        return "/v1/models"
    }
}

public final class NagramSettings {
    public static let shared = NagramSettings()
    public static let chatListAllChatsFolderId: Int32 = -1
    public static let recentStickerLimitOptions: [Int32] = [20, 30, 40, 50, 60, 80, 100, 120, 150, 200]
    public static let messageDoubleTapSameAsUnified = "sameAsUnified"

    public static func isICloudSyncEnabled(defaults: UserDefaults = .standard) -> Bool {
        return NagramSettingsCloudSync.isEnabled(defaults: defaults)
    }

    private init() {
        NagramSettingsCloudSync.shared.start()
    }

    /// iCloud KVS 同步开关。保持本地-only,避免关闭同步的选择被云端覆盖。
    public var iCloudSyncEnabled: Bool {
        get {
            return Self.isICloudSyncEnabled()
        }
        set {
            NagramSettingsCloudSync.shared.setEnabled(newValue)
        }
    }

    // MARK: 波次 1 — force-copy（已落地，key 保持不变以平滑迁移）
    @NagramDefault("nagram.forceCopyEnabled", false)
    public var forceCopyEnabled: Bool

    // MARK: 敏感内容
    /// 跳过 18+ 媒体确认弹窗，直接揭示当前媒体
    @NagramDefault("nagram.skipSensitiveContentWarning", false)
    public var skipSensitiveContentWarning: Bool

    // MARK: 波次 3 批 A — 纯 UI 单点开关
    /// 隐藏消息反应
    @NagramDefault("nagram.hideReactions", false)
    public var hideReactions: Bool
    /// 禁止上滑到下一个未读频道
    @NagramDefault("nagram.disableScrollToNextChannel", false)
    public var disableScrollToNextChannel: Bool
    /// 禁止上滑到下一个主题
    @NagramDefault("nagram.disableScrollToNextTopic", false)
    public var disableScrollToNextTopic: Bool
    /// 禁用图库内相机
    @NagramDefault("nagram.disableGalleryCamera", false)
    public var disableGalleryCamera: Bool
    /// 禁用图库内相机实时预览
    @NagramDefault("nagram.disableGalleryCameraPreview", false)
    public var disableGalleryCameraPreview: Bool
    /// 隐藏「以频道身份发送」按钮
    @NagramDefault("nagram.disableSendAsButton", false)
    public var disableSendAsButton: Bool
    /// 隐藏语音录制按钮
    @NagramDefault("nagram.hideRecordingButton", false)
    public var hideRecordingButton: Bool
    /// 消息时间戳显示秒
    @NagramDefault("nagram.secondsInMessages", false)
    public var secondsInMessages: Bool
    /// 在转发来源后显示原始消息时间
    @NagramDefault("nagram.showForwardedMessageDate", false)
    public var showForwardedMessageDate: Bool
    /// 隐藏频道底部面板按钮
    @NagramDefault("nagram.hideChannelBottomButton", false)
    public var hideChannelBottomButton: Bool
    /// 隐藏赞助消息和代理赞助频道入口
    @NagramDefault("nagram.hideSponsoredMessages", false)
    public var hideSponsoredMessages: Bool
    /// 隐藏一对一私聊中对方的输入、上传和选贴纸状态
    @NagramDefault("nagram.hidePrivateChatActivities", false)
    public var hidePrivateChatActivities: Bool
    /// 通话前确认（默认关 = 保持原生无确认）
    @NagramDefault("nagram.confirmCalls", false)
    public var confirmCalls: Bool
    /// 资料页显示数据中心 DC
    @NagramDefault("nagram.showDC", false)
    public var showDC: Bool
    /// 控件玻璃高亮（默认开 = 保持原生交互反馈）
    @NagramDefault("nagram.controlHighlightEnabled", true)
    public var controlHighlightEnabled: Bool
    /// Liquid Glass 色调模式（默认跟随系统 = 保持原生 Liquid Glass / 降低透明度行为）
    @NagramDefault("nagram.glassTransparencyMode", NagramGlassTransparencyMode.system.rawValue)
    public var glassTransparencyMode: String
    /// 自定义 Liquid Glass 色调强度百分比（0–100，默认 100 = 当前视觉）
    @NagramDefault("nagram.glassTransparencyPercent", Int32(100))
    public var glassTransparencyPercent: Int32

    // MARK: 波次 3 批 B — UI 中改
    /// 底栏布局完整配置。新逻辑只读写这一份模型。
    public var bottomBarSettings: NagramBottomBarSettings {
        get {
            return NagramBottomBarSettings.load()
        }
        set {
            newValue.save()
        }
    }
    /// 隐藏底部标签栏。兼容旧调用点,实际映射到 bottomBarSettings。
    public var hideTabBar: Bool {
        get {
            return !self.bottomBarSettings.isBottomBarVisible
        }
        set {
            var settings = self.bottomBarSettings
            settings.isBottomBarVisible = !newValue
            self.bottomBarSettings = settings
        }
    }
    /// 隐藏底栏联系人入口。兼容旧调用点,外置联系人不算隐藏。
    public var hideTabBarContacts: Bool {
        get {
            return !self.bottomBarSettings.isVisible(.contacts)
        }
        set {
            var settings = self.bottomBarSettings
            if newValue != settings.hiddenItems.contains(.contacts) {
                settings.toggleHidden(.contacts)
            }
            self.bottomBarSettings = settings
        }
    }
    /// 隐藏底栏消息入口。兼容旧调用点,外置聊天不算隐藏。
    public var hideTabBarChats: Bool {
        get {
            return !self.bottomBarSettings.isVisible(.chats)
        }
        set {
            var settings = self.bottomBarSettings
            if newValue != settings.hiddenItems.contains(.chats) {
                settings.toggleHidden(.chats)
            }
            self.bottomBarSettings = settings
        }
    }
    /// 隐藏底栏设置入口。兼容旧调用点,外置设置不算隐藏。
    public var hideTabBarSettings: Bool {
        get {
            return !self.bottomBarSettings.isVisible(.settings)
        }
        set {
            var settings = self.bottomBarSettings
            if newValue != settings.hiddenItems.contains(.settings) {
                settings.toggleHidden(.settings)
            }
            self.bottomBarSettings = settings
        }
    }
    /// 旧 key 名保留: true 表示隐藏首页顶部搜索。
    public var showTabBarSearch: Bool {
        get {
            return !self.bottomBarSettings.topSearchVisible
        }
        set {
            var settings = self.bottomBarSettings
            settings.topSearchVisible = !newValue
            self.bottomBarSettings = settings
        }
    }
    /// 展示宽底栏（默认开 = 保持原生均分宽度）。兼容旧调用点。
    public var wideTabBar: Bool {
        get {
            return self.bottomBarSettings.buttonWidthFillRatio >= 100
        }
        set {
            var settings = self.bottomBarSettings
            settings.buttonWidthFillRatio = newValue ? 100 : 0
            settings.widthMode = newValue ? .full : .adaptive
            if newValue {
                settings.slotMode = .visibleOnly
                settings.alignment = .leftCenter
            } else {
                settings.slotMode = .preserveHidden
                settings.alignment = .spaceBetween
            }
            self.bottomBarSettings = settings
        }
    }
    /// 贴纸尺寸百分比（50–200，默认 100）
    @NagramDefault("nagram.stickerSize", Int32(100))
    public var stickerSize: Int32
    /// 显示贴纸时间戳（默认开 = 原生行为）
    @NagramDefault("nagram.stickerTimestamp", true)
    public var stickerTimestamp: Bool
    /// 最近贴纸数量上限（默认 20 = Telegram 原生行为）
    @NagramDefault("nagram.recentStickerLimit", Int32(20))
    public var recentStickerLimit: Int32
    /// 上滑视频开启画中画（"up" / "none"）
    @NagramDefault("nagram.videoPIPSwipeDirection", "up")
    public var videoPIPSwipeDirection: String
    /// 对话列表横滑行为（"both" / "switch" / "quick" / "none"）
    @NagramDefault("nagram.chatListSwipeAction", NagramChatListSwipeAction.both.rawValue)
    public var chatListSwipeAction: String
    /// 下拉展示归档后自动进入归档
    @NagramDefault("nagram.openArchiveOnPull", false)
    public var openArchiveOnPull: Bool
    /// 在非“全部会话”分组顶部展示归档入口（默认关 = 保持 Telegram 原生行为）
    @NagramDefault("nagram.showArchiveInFolders", false)
    public var showArchiveInFolders: Bool
    /// 对话列表启动分组（"telegram" / "last" / "specific"）
    @NagramDefault("nagram.chatListStartupFolderMode", NagramChatListStartupFolderMode.telegramDefault.rawValue)
    public var chatListStartupFolderMode: String
    /// 首页分组标签紧凑布局
    @NagramDefault("nagram.chatListFolderTabsCompact", false)
    public var chatListFolderTabsCompact: Bool
    /// 隐藏首页的“全部会话”分组（至少存在一个自定义分组时生效）
    @NagramDefault("nagram.hideAllChatsFolder", false)
    public var hideAllChatsFolder: Bool
    /// 首页分组标签显示方式（"text" / "icon" / "both"）
    @NagramDefault("nagram.chatListFolderTabDisplayMode", NagramChatListFolderTabDisplayMode.text.rawValue)
    public var chatListFolderTabDisplayMode: String
    /// 对话列表消息预览样式（"three" / "two"）
    @NagramDefault("nagram.chatListMessagePreviewStyle", NagramChatListMessagePreviewStyle.three.rawValue)
    public var chatListMessagePreviewStyle: String
    /// 紧凑对话列表（压缩列表行高）
    @NagramDefault("nagram.chatListCompact", false)
    public var chatListCompact: Bool
    /// 最近会话快捷入口
    @NagramDefault("nagram.recentChatsEnabled", false)
    public var recentChatsEnabled: Bool
    /// 点击消息行打开上下文菜单（默认关 = 保持原生长按）
    @NagramDefault("nagram.tapMessageRowToOpenContextMenu", false)
    public var tapMessageRowToOpenContextMenu: Bool
    /// 双击消息动作（默认发送回应 = 保持 iOS 原生行为）
    @NagramDefault("nagram.messageDoubleTapAction", NagramMessageDoubleTapAction.sendReaction.rawValue)
    public var messageDoubleTapAction: String
    /// 无编辑权限消息的双击动作（默认跟随统一动作）
    @NagramDefault("nagram.messageDoubleTapActionWithoutEditPermission", NagramSettings.messageDoubleTapSameAsUnified)
    public var messageDoubleTapActionWithoutEditPermission: String
    /// 资料页显示用户数字 ID（默认关 = 保持原生）
    @NagramDefault("nagram.showProfileId", false)
    public var showProfileId: Bool

    // MARK: 波次 3 批 C — 底层加速
    /// 上传加速
    @NagramDefault("nagram.uploadSpeedBoost", false)
    public var uploadSpeedBoost: Bool
    /// 下载加速档位（"none" / "medium" / "maximum"）
    @NagramDefault("nagram.downloadSpeedBoost", "none")
    public var downloadSpeedBoost: String

    // MARK: NAGRAM — 翻译 provider 设置
    /// 翻译 provider（Telegram MTProto 或 Nagram 外部 provider）。
    @NagramDefault("nagram.translationProvider", NagramTranslationProvider.telegram.rawValue)
    public var translationProvider: String
    /// LLM API wire format (OpenAI-compatible Chat Completions or Anthropic Messages).
    @NagramDefault("nagram.translationLLMAPIFormat", NagramTranslationLLMAPIFormat.openai.rawValue)
    public var translationLLMAPIFormat: String
    /// Optional LLM API base URL; empty uses the selected format default.
    @NagramDefault("nagram.translationLLMBaseURL", "")
    public var translationLLMBaseURL: String
    /// Optional LLM translation endpoint path/full URL; empty uses the selected format default.
    @NagramDefault("nagram.translationLLMEndpoint", "")
    public var translationLLMEndpoint: String
    /// LLM API key is intentionally stored in Keychain and excluded from iCloud sync.
    public var translationLLMAPIKey: String {
        get {
            return NagramTranslationLLMKeychain.apiKey
        }
        set {
            NagramTranslationLLMKeychain.apiKey = newValue
        }
    }
    /// OpenAI-compatible model name for LLM translation.
    @NagramDefault("nagram.translationLLMModel", "")
    public var translationLLMModel: String
    /// Optional user prompt template. Empty uses `defaultTranslationLLMPrompt`.
    @NagramDefault("nagram.translationLLMPrompt", "")
    public var translationLLMPrompt: String
    /// Include recent messages when translating chat messages with an LLM.
    @NagramDefault("nagram.translationLLMUseContext", false)
    public var translationLLMUseContext: Bool
    /// OpenAI-compatible LLM temperature in tenths (0...20).
    @NagramDefault("nagram.translationLLMTemperatureTenths", 7)
    public var translationLLMTemperatureTenths: Int32

    // MARK: 波次 3 批 D — 需新逻辑
    /// 回车键发送消息
    @NagramDefault("nagram.sendWithReturnKey", false)
    public var sendWithReturnKey: Bool
    /// 选中文本时显示文字样式工具栏
    @NagramDefault("nagram.showTextStyleToolbar", true)
    public var showTextStyleToolbar: Bool
    /// 发送时自动插入中英文空格
    @NagramDefault("nagram.enablePanguOnSending", false)
    public var enablePanguOnSending: Bool
    /// 编辑时自动插入中英文空格
    @NagramDefault("nagram.enablePanguOnEditing", false)
    public var enablePanguOnEditing: Bool
    /// 接收展示时自动插入中英文空格
    @NagramDefault("nagram.enablePanguOnReceiving", false)
    public var enablePanguOnReceiving: Bool
    /// 更宽的频道帖子
    @NagramDefault("nagram.wideChannelPosts", false)
    public var wideChannelPosts: Bool
    /// 隐藏动态（Stories）
    @NagramDefault("nagram.hideStories", false)
    public var hideStories: Bool
    /// 资料页显示注册日期（默认关 = 保持原生）
    @NagramDefault("nagram.showRegDate", false)
    public var showRegDate: Bool
    /// 群组资料页直接展示的设置项；默认不展示，用户需逐项启用。
    @NagramDefault("nagram.groupProfileSettingItems", "")
    private var groupProfileSettingItems: String
    /// 设置/资料页隐藏手机号（默认关 = 保持原生）
    @NagramDefault("nagram.hidePhoneInSettings", false)
    public var hidePhoneInSettings: Bool

    @NagramDefault("nagram.mediaMetadataEnabled", true)
    public var mediaMetadataEnabled: Bool

    @NagramDefault("nagram.fixLinkPreviews", false)
    public var fixLinkPreviews: Bool

    @NagramDefault("nagram.autoInlineBotEnabled", false)
    public var autoInlineBotEnabled: Bool

    public func isGroupProfileSettingItemVisible(_ item: NagramGroupProfileSettingItem) -> Bool {
        return self.visibleGroupProfileSettingItems.contains(item)
    }

    public func setGroupProfileSettingItemVisible(_ item: NagramGroupProfileSettingItem, visible: Bool) {
        var items = self.visibleGroupProfileSettingItems
        if visible {
            items.insert(item)
        } else {
            items.remove(item)
        }
        self.groupProfileSettingItems = NagramGroupProfileSettingItem.allCases
            .filter { items.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
    }

    private var visibleGroupProfileSettingItems: Set<NagramGroupProfileSettingItem> {
        return Set(self.groupProfileSettingItems.split(separator: ",").compactMap {
            NagramGroupProfileSettingItem(rawValue: String($0))
        })
    }

}

private func nagramTranslationLLMURL(baseURLString: String, endpoint: String, defaultBaseURL: String, defaultEndpoint: String) -> URL? {
    let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    if let url = URL(string: trimmedEndpoint), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
        return url
    }

    let baseString = baseURLString.isEmpty ? defaultBaseURL : baseURLString
    guard var components = URLComponents(string: baseString), let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
        return nil
    }

    var basePath = components.percentEncodedPath
    while basePath.hasSuffix("/") {
        basePath.removeLast()
    }

    var endpointPath = trimmedEndpoint.isEmpty ? defaultEndpoint : trimmedEndpoint
    if !endpointPath.hasPrefix("/") {
        endpointPath = "/\(endpointPath)"
    }
    if basePath.hasSuffix("/v1"), endpointPath.hasPrefix("/v1/") {
        endpointPath = String(endpointPath.dropFirst(3))
    }

    components.percentEncodedPath = basePath + endpointPath
    components.percentEncodedQuery = nil
    components.fragment = nil
    return components.url
}

public extension NagramSettings {
    static let defaultTranslationLLMPrompt = "Translate to @toLang:\n\n@text"

    var recentStickerLimitValue: Int {
        guard NagramSettings.recentStickerLimitOptions.contains(self.recentStickerLimit) else {
            self.recentStickerLimit = 20
            return 20
        }
        return Int(self.recentStickerLimit)
    }

    var chatListSwipeActionMode: NagramChatListSwipeAction {
        return NagramChatListSwipeAction(rawValue: self.chatListSwipeAction) ?? .both
    }

    var chatListStartupFolderModeValue: NagramChatListStartupFolderMode {
        return NagramChatListStartupFolderMode(rawValue: self.chatListStartupFolderMode) ?? .telegramDefault
    }

    var chatListFolderTabDisplayModeValue: NagramChatListFolderTabDisplayMode {
        return NagramChatListFolderTabDisplayMode(rawValue: self.chatListFolderTabDisplayMode) ?? .text
    }

    var chatListMessagePreviewStyleMode: NagramChatListMessagePreviewStyle {
        if self.chatListCompact {
            if self.chatListMessagePreviewStyle != NagramChatListMessagePreviewStyle.two.rawValue {
                self.chatListMessagePreviewStyle = NagramChatListMessagePreviewStyle.two.rawValue
            }
            return .two
        }
        if UserDefaults.standard.object(forKey: "nagram.chatListMessagePreviewStyle") == nil, let legacyValue = UserDefaults.standard.string(forKey: "nagram.chatListLines"), let legacyMode = NagramChatListMessagePreviewStyle(rawValue: legacyValue) {
            return legacyMode
        }
        return NagramChatListMessagePreviewStyle(rawValue: self.chatListMessagePreviewStyle) ?? .three
    }

    var glassTransparencyModeValue: NagramGlassTransparencyMode {
        return NagramGlassTransparencyMode(rawValue: self.glassTransparencyMode) ?? .system
    }

    var glassTransparencyPercentValue: Int32 {
        return max(0, min(100, self.glassTransparencyPercent))
    }

    var glassTransparencyFactor: Double {
        guard self.glassTransparencyModeValue == .custom else {
            return 1.0
        }
        return Double(self.glassTransparencyPercentValue) / 100.0
    }

    var glassTransparencyFollowsSystem: Bool {
        return self.glassTransparencyModeValue != .custom
    }

    var messageDoubleTapActionValue: NagramMessageDoubleTapAction {
        guard let value = NagramMessageDoubleTapAction(rawValue: self.messageDoubleTapAction) else {
            self.messageDoubleTapAction = NagramMessageDoubleTapAction.sendReaction.rawValue
            return .sendReaction
        }
        return value
    }

    var messageDoubleTapActionWithoutEditPermissionValue: String {
        let value = self.messageDoubleTapActionWithoutEditPermission
        if value == NagramSettings.messageDoubleTapSameAsUnified {
            return value
        }
        guard let action = NagramMessageDoubleTapAction(rawValue: value), action != .edit else {
            self.messageDoubleTapActionWithoutEditPermission = NagramSettings.messageDoubleTapSameAsUnified
            return NagramSettings.messageDoubleTapSameAsUnified
        }
        return action.rawValue
    }

    func resolvedMessageDoubleTapAction(canEditMessage: Bool) -> NagramMessageDoubleTapAction {
        if !canEditMessage, let action = NagramMessageDoubleTapAction(rawValue: self.messageDoubleTapActionWithoutEditPermissionValue) {
            return action
        }
        return self.messageDoubleTapActionValue
    }

    var translationProviderValue: NagramTranslationProvider {
        guard let value = NagramTranslationProvider(rawValue: self.translationProvider) else {
            self.translationProvider = NagramTranslationProvider.telegram.rawValue
            return .telegram
        }
        return value
    }

    var translationLLMAPIFormatValue: NagramTranslationLLMAPIFormat {
        guard let value = NagramTranslationLLMAPIFormat(rawValue: self.translationLLMAPIFormat) else {
            self.translationLLMAPIFormat = NagramTranslationLLMAPIFormat.openai.rawValue
            return .openai
        }
        return value
    }

    var translationLLMBaseURLValue: String {
        return self.translationLLMBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var translationLLMEndpointValue: String {
        return self.translationLLMEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var translationLLMAPIKeyValue: String {
        return self.translationLLMAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var translationLLMModelValue: String {
        return self.translationLLMModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var translationLLMPromptValue: String {
        return self.translationLLMPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.defaultTranslationLLMPrompt : self.translationLLMPrompt
    }

    var translationLLMTemperatureTenthsValue: Int32 {
        return max(0, min(20, self.translationLLMTemperatureTenths))
    }

    var translationLLMTemperatureValue: Double {
        return Double(self.translationLLMTemperatureTenthsValue) / 10.0
    }

    func translationLLMTranslationURL() -> URL? {
        let format = self.translationLLMAPIFormatValue
        return nagramTranslationLLMURL(baseURLString: self.translationLLMBaseURLValue, endpoint: self.translationLLMEndpointValue, defaultBaseURL: format.defaultBaseURL, defaultEndpoint: format.defaultTranslationEndpoint)
    }

    func translationLLMModelsURL() -> URL? {
        let format = self.translationLLMAPIFormatValue
        return nagramTranslationLLMURL(baseURLString: self.translationLLMBaseURLValue, endpoint: format.defaultModelsEndpoint, defaultBaseURL: format.defaultBaseURL, defaultEndpoint: format.defaultModelsEndpoint)
    }

    func chatListStartupSpecificFolderId(accountPeerId: Int64) -> Int32? {
        return self.chatListStartupFolderId(forKey: self.chatListStartupSpecificFolderKey(accountPeerId: accountPeerId))
    }

    func setChatListStartupSpecificFolderId(_ folderId: Int32?, accountPeerId: Int64) {
        self.setChatListStartupFolderId(folderId, forKey: self.chatListStartupSpecificFolderKey(accountPeerId: accountPeerId))
    }

    func chatListStartupLastFolderId(accountPeerId: Int64) -> Int32? {
        return self.chatListStartupFolderId(forKey: self.chatListStartupLastFolderKey(accountPeerId: accountPeerId))
    }

    func setChatListStartupLastFolderId(_ folderId: Int32?, accountPeerId: Int64) {
        self.setChatListStartupFolderId(folderId, forKey: self.chatListStartupLastFolderKey(accountPeerId: accountPeerId))
    }

    var stickerSizeCoefficient: Float {
        let clampedSize = max(Int32(50), min(Int32(200), self.stickerSize))
        return Float(clampedSize) / 100.0
    }

    /// 下载分片大小：按加速档位放大（接入 TelegramCore FetchV2）。仿 SG getSGDownloadPartSize。
    func downloadPartSize(default defaultValue: Int64, fileSize: Int64?) -> Int64 {
        let smallFileThreshold: Int64 = 1 * 1024 * 1024
        switch downloadSpeedBoost {
        case "medium":
            if let fileSize, fileSize <= smallFileThreshold { return defaultValue }
            return 512 * 1024
        case "maximum":
            if let fileSize, fileSize <= smallFileThreshold { return defaultValue }
            return 1024 * 1024
        default:
            return defaultValue
        }
    }

    /// 下载最大并发分片数：按加速档位放大。仿 SG getSGMaxPendingParts。
    func maxPendingDownloadParts(default defaultValue: Int) -> Int {
        switch downloadSpeedBoost {
        case "medium": return 8
        case "maximum": return 12
        default: return defaultValue
        }
    }
}

private extension NagramSettings {
    func chatListStartupSpecificFolderKey(accountPeerId: Int64) -> String {
        return "nagram.chatListStartupSpecificFolder.\(accountPeerId)"
    }

    func chatListStartupLastFolderKey(accountPeerId: Int64) -> String {
        return "nagram.chatListStartupLastFolder.\(accountPeerId)"
    }

    func chatListStartupFolderId(forKey key: String) -> Int32? {
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return nil
        }
        return Int32(UserDefaults.standard.integer(forKey: key))
    }

    func setChatListStartupFolderId(_ folderId: Int32?, forKey key: String) {
        guard let folderId else {
            NagramSettingsCloudSync.shared.removeObject(forKey: key)
            return
        }
        NagramSettingsCloudSync.shared.set(Int(folderId), forKey: key)
    }
}
