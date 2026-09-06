import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences

/// Seeds only the disposable demo database, before the normal account UI starts.
public func prepareNagramDemo(accountManager: AccountManager<TelegramAccountManagerTypes>, rootPath: String, encryptionParameters: ValueBoxEncryptionParameters) -> Signal<Void, NoError> {
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
        return accountTransaction(rootPath: rootPath, id: id, encryptionParameters: encryptionParameters, isReadOnly: false, transaction: { _, transaction -> Void in
            seedNagramDemo(transaction: transaction)
        })
        |> `catch` { _ -> Signal<Void, NoError> in
            preconditionFailure("Could not initialize demo database; relaunch with --demo to reset it")
        }
    }
}

private func demoUser(_ id: Int64, _ name: String) -> TelegramUser {
    return TelegramUser(
        id: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(id)),
        accessHash: nil, firstName: name, lastName: nil, username: nil, phone: nil,
        photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil,
        usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil,
        profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil,
        verificationIconFileId: nil
    )
}

private func seedNagramDemo(transaction: Transaction) {
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
        id: PeerId(namespace: Namespaces.Peer.CloudGroup, id: PeerId.Id._internalFromInt64Value(900006)),
        title: text("周末漫游计划", "Weekend Wanderers"), photo: [], participantCount: 5, role: .member,
        membership: .Member, flags: [], defaultBannedRights: nil,
        migrationReference: nil, creationDate: timestamp - 86400, version: 1
    )
    let channel = TelegramChannel(
        id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(900007)),
        accessHash: nil, title: text("Nagram 灵感站", "Nagram Inspiration"), username: nil, photo: [],
        creationDate: timestamp - 86400, version: 1, participationStatus: .member,
        info: .broadcast(TelegramChannelBroadcastInfo(flags: [])), flags: [],
        restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil,
        usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil,
        profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil,
        approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil,
        sendPaidMessageStars: nil, linkedMonoforumId: nil
    )
    let peers: [Peer] = [me, lin, summer, alex, yu, group, channel]
    transaction.updatePeersInternal(peers, update: { _, peer in peer })
    // Private chat history waits for a known business intro, even when there is none.
    transaction.updatePeerCachedData(peerIds: Set([me.id, lin.id, summer.id, alex.id, yu.id]), update: { _, _ in
        CachedUserData().withUpdatedBusinessIntro(nil).withUpdatedPeerStatusSettings(PeerStatusSettings())
    })
    transaction.updatePeerPresencesInternal(presences: [
        lin.id: TelegramUserPresence(status: .present(until: Int32.max), lastActivity: timestamp)
    ], merge: { _, presence in presence })
    transaction.setState(AuthorizedAccountState(
        isTestingEnvironment: true, masterDatacenterId: 2, peerId: me.id,
        state: AuthorizedAccountState.State(pts: 1, qts: 0, date: timestamp, seq: 0),
        invalidatedChannels: []
    ))
    transaction.updatePreferencesEntry(key: PreferencesKeys.contactsSettings, { _ in
        PreferencesEntry(ContactsSettings(synchronizeContacts: false))
    })

    let chats: [(Peer, [(PeerId, String)], Int32)] = [
        (channel, [
            (channel.id, text("让每一次交流，都更合心意。", "Make every conversation feel more like you.")),
            (channel.id, text("简洁的界面，自由的表达。\n在 Nagram，找到属于你的聊天方式。 ✨", "A clean interface. Room to be yourself.\nFind your own way to chat with Nagram. ✨"))
        ], 0),
        (lin, [
            (lin.id, text("早上好！今天的阳光刚刚好 ☀️", "Morning! The sunshine is just perfect today ☀️")),
            (me.id, text("适合出门走走，也适合换个新主题。", "Perfect for a walk. And a fresh new theme.")),
            (lin.id, text("这个配色好舒服，像把春天装进了聊天里。", "These colors feel like a little bit of spring in our chat.")),
            (me.id, text("字体和气泡也可以一起调整，刚好是喜欢的样子。", "You can customize the font and bubbles too. Just how you like it.")),
            (lin.id, text("那就周末见，我们去河边散步 🌿", "See you this weekend for a walk by the river 🌿"))
        ], 2),
        (group, [
            (summer.id, text("周六的路线整理好了：咖啡店 → 美术馆 → 河边日落", "Saturday's plan: coffee → art gallery → sunset by the river")),
            (yu.id, text("我带相机！📷", "I'll bring my camera! 📷")),
            (me.id, text("听起来很棒，下午两点出发。", "Sounds lovely. Let's head out at two.")),
            (lin.id, text("不用赶时间，慢慢走就好。", "No rush. Let's take the scenic route."))
        ], 3),
        (summer, [
            (summer.id, text("分享一句今天读到的话：", "A line I came across today:")),
            (summer.id, text("生活的美好，藏在愿意停下来的瞬间。", "The lovely things in life are waiting for us to slow down.")),
            (me.id, text("收藏了，留给忙碌的时候看。", "Saved. A little reminder for the busy days."))
        ], 0),
        (alex, [
            (alex.id, text("多一点色彩，多一点快乐。", "A little more color, a little more joy.")),
            (me.id, text("这正是我想要的感觉！", "That's exactly what I had in mind!")),
            (alex.id, text("周末见 ✨", "See you this weekend ✨"))
        ], 1),
        (yu, [
            (me.id, text("上次提到的那家书店，找到了吗？", "Did you find that bookshop you mentioned?")),
            (yu.id, text("找到了！靠窗的位置很安静，下次一起去 📚", "Yes! The window seats are so peaceful. Let's go together 📚"))
        ], 0),
        (me, [(me.id, text("灵感备忘\n\n☑ 换一个喜欢的主题\n☑ 整理收藏的句子\n☐ 记录周末的小美好", "Little inspirations\n\n☑ Try a new theme\n☑ Save a few favorite lines\n☐ Capture the little joys this weekend"))], 0)
    ]

    for (chatIndex, chat) in chats.enumerated() {
        let (peer, texts, unreadCount) = chat
        let firstId = Int32(chatIndex * 100 + 1)
        let messages = texts.enumerated().map { index, item -> StoreMessage in
            return StoreMessage(
                id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: firstId + Int32(index)),
                customStableId: nil, globallyUniqueId: nil, groupingKey: nil, threadId: nil,
                timestamp: timestamp - Int32(chatIndex * 900 + (texts.count - index - 1) * 60),
                flags: item.0 == me.id ? [] : [.Incoming], tags: [], globalTags: [], localTags: [],
                forwardInfo: nil, authorId: item.0, text: item.1, attributes: [], media: []
            )
        }
        let _ = transaction.addMessages(messages, location: .Random)
        transaction.updatePeerChatListInclusion(peer.id, inclusion: .ifHasMessagesOrOneOf(
            groupId: .root, pinningIndex: chatIndex == 0 ? 0 : nil, minTimestamp: nil
        ))
        let lastId = firstId + Int32(texts.count) - 1
        let unreadIds = texts.enumerated().compactMap { index, item -> Int32? in
            return item.0 == me.id ? nil : firstId + Int32(index)
        }.suffix(Int(unreadCount))
        transaction.resetIncomingReadStates([peer.id: [Namespaces.Message.Cloud: .idBased(
            maxIncomingReadId: unreadIds.first.map { $0 - 1 } ?? lastId, maxOutgoingReadId: lastId,
            maxKnownId: lastId, count: Int32(unreadIds.count), markedUnread: false
        )]])
        transaction.removeHole(peerId: peer.id, threadId: nil, namespace: Namespaces.Message.Cloud, space: .everywhere, range: 1 ... Int32.max - 1)
    }
    for groupId in [PeerGroupId.root, Namespaces.PeerGroup.archive] {
        for hole in transaction.allChatListHoles(groupId: groupId) {
            transaction.replaceChatListHole(groupId: groupId, index: hole.index, hole: nil)
        }
    }
}
