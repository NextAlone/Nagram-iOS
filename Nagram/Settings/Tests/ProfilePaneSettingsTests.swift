import Foundation
import NagramSettings
import XCTest

final class ProfilePaneSettingsTests: XCTestCase {
    private let suiteName = "NagramProfilePaneTests.\(UUID().uuidString)"
    private var defaults: UserDefaults!
    private let settings = NagramSettings.shared

    override func setUpWithError() throws {
        self.defaults = try XCTUnwrap(UserDefaults(suiteName: self.suiteName))
    }

    override func tearDown() {
        self.defaults.removePersistentDomain(forName: self.suiteName)
    }

    func testScopedEditInheritsLegacyOrderAndVisibilityWithoutChangingOtherTypes() {
        let panes: [NagramProfilePane] = [.media, .files, .links]
        self.defaults.set("links,media,files", forKey: "nagram.profilePanes.order")
        self.defaults.set("files", forKey: "nagram.profilePanes.hidden")

        for scope in NagramProfilePaneScope.allCases {
            let state = self.settings.profilePaneSettings(for: scope, defaults: self.defaults)
            XCTAssertEqual(state.ordered(panes), [.links, .media, .files])
            XCTAssertTrue(state.isHidden(.files))
        }

        self.settings.setProfilePaneHidden(false, for: .files, in: .channel, defaults: self.defaults)
        self.defaults.set("media,links,files", forKey: "nagram.profilePanes.order")
        self.settings.setProfilePaneOrder([.files, .links, .media], in: .bot, defaults: self.defaults)

        let channel = self.settings.profilePaneSettings(for: .channel, defaults: self.defaults)
        XCTAssertEqual(channel.ordered(panes), [.links, .media, .files])
        XCTAssertFalse(channel.isHidden(.files))

        let bot = self.settings.profilePaneSettings(for: .bot, defaults: self.defaults)
        XCTAssertEqual(bot.ordered(panes), [.files, .links, .media])
        XCTAssertTrue(bot.isHidden(.files))

        let user = self.settings.profilePaneSettings(for: .user, defaults: self.defaults)
        XCTAssertEqual(user.ordered(panes), [.media, .links, .files])
        XCTAssertTrue(user.isHidden(.files))
        XCTAssertEqual(self.defaults.string(forKey: "nagram.profilePanes.hidden"), "files")
    }

    func testMainPaneWarningReflectsTheFirstVisibleTabAfterServerChange() {
        let panes: [NagramProfilePane] = [.gifts, .media, .files, .stories]
        func overrides(_ pane: NagramProfilePane) -> Bool {
            return self.settings.profilePaneSettings(for: .channel, defaults: self.defaults).overridesMainPane(pane, in: panes)
        }

        XCTAssertFalse(overrides(.files))
        self.settings.setProfilePaneOrder([.media, .files], in: .channel, defaults: self.defaults)
        XCTAssertTrue(overrides(.files))
        XCTAssertFalse(overrides(.stories))
        self.settings.setProfilePaneHidden(true, for: .media, in: .channel, defaults: self.defaults)
        XCTAssertTrue(overrides(.media))
        XCTAssertTrue(overrides(.files)) // Gifts remains ahead of Files after the hidden Media slot.
        self.settings.setProfilePaneHidden(true, for: .gifts, in: .channel, defaults: self.defaults)
        XCTAssertFalse(overrides(.files))
    }

    func testReplacingServerMainTabUsesTheNaturalOrder() {
        let naturalOrder: [NagramProfilePane] = [.stories, .gifts, .media]
        self.settings.setProfilePaneOrder([.stories, .media], in: .channel, defaults: self.defaults)
        self.settings.setProfilePaneHidden(true, for: .stories, in: .channel, defaults: self.defaults)

        let settings = self.settings.profilePaneSettings(for: .channel, defaults: self.defaults)
        XCTAssertFalse(settings.overridesMainPane(.media, in: naturalOrder))
    }

    func testOnlyRelevantPanesAreListedInEachScope() {
        let media: Set<NagramProfilePane> = [.media, .files, .music, .voice, .links, .gifs, .polls]
        let expected: [NagramProfilePaneScope: Set<NagramProfilePane>] = [
            .user: media.union([.stories, .gifts, .groupsInCommon, .savedMessages]),
            .bot: media.union([.stories, .groupsInCommon, .savedMessages, .botPreview, .similarBots]),
            .group: media.union([.members, .stories, .savedMessages]),
            .channel: media.union([.stories, .gifts, .savedMessages, .similarChannels]),
            .myProfile: [.stories, .gifts, .storyArchive],
            .savedMessages: media.union([.savedMessagesChats])
        ]
        for scope in NagramProfilePaneScope.allCases {
            XCTAssertEqual(scope.panes, NagramProfilePane.allCases.filter { expected[scope]!.contains($0) })
        }
    }
}
