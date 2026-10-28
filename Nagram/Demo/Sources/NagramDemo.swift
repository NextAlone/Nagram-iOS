import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences

/// Seeds only the disposable demo database, before the normal account UI starts.
public func prepareNagramDemo(accountManager: AccountManager<TelegramAccountManagerTypes>, rootPath: String, encryptionParameters: EngineValueBoxEncryptionParameters) -> Signal<Void, NoError> {
    precondition(rootPath.contains("/nagram-demo-data/"), "Demo data requires its isolated directory")
    return accountManager.transaction { transaction -> AccountRecordId in
        let themeSettings = PresentationThemeSettings.defaultSettings.withUpdatedAutomaticThemeSwitchSetting(
            AutomaticThemeSwitchSetting(force: false, trigger: .explicitNone, theme: .builtin(.night))
        )
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.presentationThemeSettings, { _ in
            return EnginePreferencesEntry(themeSettings)
        })
        let id = transaction.createRecord([.environment(AccountEnvironmentAttribute(environment: .test))])
        transaction.setCurrentId(id)
        return id
    }
    |> mapToSignal { id -> Signal<Void, NoError> in
        return seedNagramDemo(rootPath: rootPath, id: id, encryptionParameters: encryptionParameters)
        |> `catch` { _ -> Signal<Void, NoError> in
            preconditionFailure("Could not initialize demo database; relaunch with --demo to reset it")
        }
    }
}

private func demoUser(_ id: Int64, _ name: String) -> TelegramUser {
    return TelegramUser(
        id: EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(id)),
        accessHash: nil, firstName: name, lastName: nil, username: nil, phone: nil,
        photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil,
        usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil,
        profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil,
        verificationIconFileId: nil
    )
}

private func seedNagramDemo(rootPath: String, id: AccountRecordId, encryptionParameters: EngineValueBoxEncryptionParameters) -> Signal<Void, AccountTransactionError> {
    let language: String
    if let index = CommandLine.arguments.firstIndex(of: "--demo-language") {
        guard index + 1 < CommandLine.arguments.count, ["zh", "en"].contains(CommandLine.arguments[index + 1]) else {
            preconditionFailure("--demo-language requires zh or en")
        }
        language = CommandLine.arguments[index + 1]
    } else {
        language = "zh"
    }
    func text(_ chinese: String, _ english: String) -> String {
        return language == "en" ? english : chinese
    }

    let me = demoUser(900001, "Nagram Demo")
    let lin = demoUser(900002, text("林间", "Lin"))
    let summer = demoUser(900003, text("夏日来信", "Summer"))
    let alex = demoUser(900004, "Alex")
    let yu = demoUser(900005, text("小鱼", "Xiaoyu"))
    // Keep relative dates current, with deterministic times and ordering each day.
    let day = Calendar.current.startOfDay(for: Date())
    let timestamp = Int32(day.timeIntervalSince1970) + 9 * 3600 + 41 * 60
    let group = TelegramGroup(
        id: EnginePeer.Id(namespace: Namespaces.Peer.CloudGroup, id: EnginePeer.Id.Id._internalFromInt64Value(900006)),
        title: text("周末漫游计划", "Weekend Wanderers"), photo: [], participantCount: 5, role: .member,
        membership: .Member, flags: [], defaultBannedRights: nil,
        migrationReference: nil, creationDate: timestamp - 86400, version: 1
    )
    let channel = TelegramChannel(
        id: EnginePeer.Id(namespace: Namespaces.Peer.CloudChannel, id: EnginePeer.Id.Id._internalFromInt64Value(900007)),
        accessHash: nil, title: text("Nagram 灵感站", "Nagram Inspiration"), username: nil, photo: [],
        creationDate: timestamp - 86400, version: 1, participationStatus: .member,
        info: .broadcast(TelegramChannelBroadcastInfo(flags: [])), flags: [],
        restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil,
        usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil,
        profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil,
        approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil,
        sendPaidMessageStars: nil, linkedMonoforumId: nil
    )
    let peers: [EnginePeer] = [.user(me), .user(lin), .user(summer), .user(alex), .user(yu), .legacyGroup(group), .channel(channel)]

    let chats: [(peerId: EnginePeer.Id, messages: [(authorId: EnginePeer.Id, text: String)], unreadCount: Int32)] = [
        (channel.id, [
            (channel.id, text("让每一次交流，都更合心意。", "Make every conversation feel more like you.")),
            (channel.id, text("简洁的界面，自由的表达。\n在 Nagram，找到属于你的聊天方式。 ✨", "A clean interface. Room to be yourself.\nFind your own way to chat with Nagram. ✨"))
        ], 0),
        (lin.id, [
            (lin.id, text("早上好！今天的阳光刚刚好 ☀️", "Morning! The sunshine is just perfect today ☀️")),
            (me.id, text("适合出门走走，也适合换个新主题。", "Perfect for a walk. And a fresh new theme.")),
            (lin.id, text("这个配色好舒服，像把春天装进了聊天里。", "These colors feel like a little bit of spring in our chat.")),
            (me.id, text("字体和气泡也可以一起调整，刚好是喜欢的样子。", "You can customize the font and bubbles too. Just how you like it.")),
            (lin.id, text("那就周末见，我们去河边散步 🌿", "See you this weekend for a walk by the river 🌿"))
        ], 2),
        (group.id, [
            (summer.id, text("周六的路线整理好了：咖啡店 → 美术馆 → 河边日落", "Saturday's plan: coffee → art gallery → sunset by the river")),
            (yu.id, text("我带相机！📷", "I'll bring my camera! 📷")),
            (me.id, text("听起来很棒，下午两点出发。", "Sounds lovely. Let's head out at two.")),
            (lin.id, text("不用赶时间，慢慢走就好。", "No rush. Let's take the scenic route."))
        ], 3),
        (summer.id, [
            (summer.id, text("分享一句今天读到的话：", "A line I came across today:")),
            (summer.id, text("生活的美好，藏在愿意停下来的瞬间。", "The lovely things in life are waiting for us to slow down.")),
            (me.id, text("收藏了，留给忙碌的时候看。", "Saved. A little reminder for the busy days."))
        ], 0),
        (alex.id, [
            (alex.id, text("多一点色彩，多一点快乐。", "A little more color, a little more joy.")),
            (me.id, text("这正是我想要的感觉！", "That's exactly what I had in mind!")),
            (alex.id, text("周末见 ✨", "See you this weekend ✨"))
        ], 1),
        (yu.id, [
            (me.id, text("上次提到的那家书店，找到了吗？", "Did you find that bookshop you mentioned?")),
            (yu.id, text("找到了！靠窗的位置很安静，下次一起去 📚", "Yes! The window seats are so peaceful. Let's go together 📚"))
        ], 0),
        (me.id, [(me.id, text("灵感备忘\n\n☑ 换一个喜欢的主题\n☑ 整理收藏的句子\n☐ 记录周末的小美好", "Little inspirations\n\n☑ Try a new theme\n☑ Save a few favorite lines\n☐ Capture the little joys this weekend"))], 0)
    ]

    return nagramSeedDemoDatabase(
        rootPath: rootPath, id: id, encryptionParameters: encryptionParameters,
        accountPeerId: me.id, peers: peers, onlinePeerIds: [lin.id], timestamp: timestamp, chats: chats
    )
}
