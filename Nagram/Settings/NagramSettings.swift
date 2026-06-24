import Foundation

// MARK: NAGRAM — 增强开关集中地。
// 数据层零 Telegram 依赖，纯 UserDefaults。每个开关一行 @NagramDefault 声明（复用核心）。
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
            UserDefaults.standard.set(newValue, forKey: key)
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

public final class NagramSettings {
    public static let shared = NagramSettings()
    private init() {}

    // MARK: 波次 1 — force-copy（已落地，key 保持不变以平滑迁移）
    @NagramDefault("nagram.forceCopyEnabled", false)
    public var forceCopyEnabled: Bool

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
    /// 隐藏频道底部面板按钮
    @NagramDefault("nagram.hideChannelBottomButton", false)
    public var hideChannelBottomButton: Bool
    /// 隐藏赞助消息和代理赞助频道入口
    @NagramDefault("nagram.hideSponsoredMessages", false)
    public var hideSponsoredMessages: Bool
    /// 通话前确认（默认关 = 保持原生无确认）
    @NagramDefault("nagram.confirmCalls", false)
    public var confirmCalls: Bool
    /// 资料页显示数据中心 DC
    @NagramDefault("nagram.showDC", false)
    public var showDC: Bool

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
                settings.alignment = .center
            } else {
                settings.slotMode = .preserveHidden
                settings.alignment = .left
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
    /// 上滑视频开启画中画（"up" / "none"）
    @NagramDefault("nagram.videoPIPSwipeDirection", "up")
    public var videoPIPSwipeDirection: String
    /// 对话列表横滑行为（"both" / "switch" / "quick" / "none"）
    @NagramDefault("nagram.chatListSwipeAction", NagramChatListSwipeAction.both.rawValue)
    public var chatListSwipeAction: String
    /// 最近会话快捷入口
    @NagramDefault("nagram.recentChatsEnabled", false)
    public var recentChatsEnabled: Bool
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

    // MARK: 波次 3 批 D — 需新逻辑
    /// 回车键发送消息
    @NagramDefault("nagram.sendWithReturnKey", false)
    public var sendWithReturnKey: Bool
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
}

public extension NagramSettings {
    var chatListSwipeActionMode: NagramChatListSwipeAction {
        return NagramChatListSwipeAction(rawValue: self.chatListSwipeAction) ?? .both
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
