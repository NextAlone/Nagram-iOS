import AccountContext
import ActivityIndicator
import AsyncDisplayKit
import Display
import Foundation
import NagramStrings
import QrCode
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import UIKit

// MARK: NAGRAM — Log in by QR code.
//
// Upstream already implements the whole token exchange, but only behind a
// debug tap on the phone entry screen that draws a bare 200pt square. The
// exchange is reused verbatim here; what this adds is a real screen for it.
//
// Telegram drives the rest: once the code is scanned the account's
// authorization state changes and AuthorizationSequenceController moves on by
// itself, so this screen only has to keep a valid token on screen and get out
// of the way.

private final class NagramQrLoginControllerNode: ASDisplayNode {
    private let presentationData: PresentationData
    private let titleNode: ImmediateTextNode
    private let textNode: ImmediateTextNode
    private let qrBackgroundNode: ASDisplayNode
    private let qrImageNode: ASImageNode
    private let activityIndicator: ActivityIndicator
    private var isCompleting = false
    private let defaultCaption: String

    init(presentationData: PresentationData) {
        self.presentationData = presentationData

        self.titleNode = ImmediateTextNode()
        self.titleNode.maximumNumberOfLines = 1
        self.titleNode.textAlignment = .center

        self.textNode = ImmediateTextNode()
        self.textNode.maximumNumberOfLines = 0
        self.textNode.textAlignment = .center
        self.textNode.lineSpacing = 0.2

        // The generated code is dark-on-light, so it needs a light plate to stay
        // scannable in the dark theme.
        self.qrBackgroundNode = ASDisplayNode()
        self.qrBackgroundNode.backgroundColor = .white
        self.qrBackgroundNode.cornerRadius = 16.0

        self.qrImageNode = ASImageNode()
        self.qrImageNode.contentMode = .scaleAspectFit

        // Visible until the first code arrives: fetching the token needs a
        // network round trip, and an empty white square reads as broken.
        self.activityIndicator = ActivityIndicator(type: .custom(presentationData.theme.list.itemAccentColor, 28.0, 2.0, false))
        self.defaultCaption = ngI18n("Nagram.QrLogin.Text", presentationData.strings.baseLanguageCode)

        super.init()

        self.backgroundColor = presentationData.theme.list.plainBackgroundColor

        let language = presentationData.strings.baseLanguageCode
        self.titleNode.attributedText = NSAttributedString(
            string: ngI18n("Nagram.QrLogin.Title", language),
            font: Font.semibold(24.0),
            textColor: presentationData.theme.list.itemPrimaryTextColor
        )
        self.textNode.attributedText = NSAttributedString(
            string: ngI18n("Nagram.QrLogin.Text", language),
            font: Font.regular(15.0),
            textColor: presentationData.theme.list.itemSecondaryTextColor
        )

        self.addSubnode(self.titleNode)
        self.addSubnode(self.qrBackgroundNode)
        self.addSubnode(self.qrImageNode)
        self.addSubnode(self.textNode)
        self.addSubnode(self.activityIndicator)
    }

    // The token has been accepted but the authorization state takes a moment to
    // catch up. Without this the screen would simply vanish and leave the user
    // looking at the intro for several seconds.
    func setCode(_ image: UIImage) {
        self.qrImageNode.image = image
        self.activityIndicator.isHidden = true
        self.setCaption(self.defaultCaption)
    }

    func setCaption(_ text: String) {
        self.textNode.attributedText = NSAttributedString(
            string: text,
            font: Font.regular(15.0),
            textColor: self.presentationData.theme.list.itemSecondaryTextColor
        )
    }

    func setCompleting(title: String, text: String) {
        self.isCompleting = true
        self.qrBackgroundNode.isHidden = true
        self.qrImageNode.isHidden = true
        self.activityIndicator.isHidden = false
        self.qrImageNode.image = nil
        self.titleNode.attributedText = NSAttributedString(string: title, font: Font.semibold(24.0), textColor: self.presentationData.theme.list.itemPrimaryTextColor)
        self.textNode.attributedText = NSAttributedString(string: text, font: Font.regular(15.0), textColor: self.presentationData.theme.list.itemSecondaryTextColor)
    }

    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let sideInset: CGFloat = 24.0 + layout.safeInsets.left
        let availableWidth = layout.size.width - sideInset * 2.0

        let titleSize = self.titleNode.updateLayout(CGSize(width: availableWidth, height: .greatestFiniteMagnitude))
        let textSize = self.textNode.updateLayout(CGSize(width: availableWidth, height: .greatestFiniteMagnitude))

        let qrSide = min(260.0, availableWidth)
        let contentHeight = titleSize.height + 28.0 + qrSide + 28.0 + textSize.height
        var originY = navigationBarHeight + max(24.0, (layout.size.height - navigationBarHeight - layout.intrinsicInsets.bottom - contentHeight) / 2.0 - 40.0)

        transition.updateFrame(node: self.titleNode, frame: CGRect(origin: CGPoint(x: floor((layout.size.width - titleSize.width) / 2.0), y: originY), size: titleSize))
        originY += titleSize.height + 28.0

        let qrFrame = CGRect(origin: CGPoint(x: floor((layout.size.width - qrSide) / 2.0), y: originY), size: CGSize(width: qrSide, height: qrSide))
        transition.updateFrame(node: self.qrBackgroundNode, frame: qrFrame)
        transition.updateFrame(node: self.qrImageNode, frame: qrFrame.insetBy(dx: 12.0, dy: 12.0))
        let indicatorSize = CGSize(width: 28.0, height: 28.0)
        transition.updateFrame(node: self.activityIndicator, frame: CGRect(origin: CGPoint(x: floor((layout.size.width - indicatorSize.width) / 2.0), y: originY + floor((qrSide - indicatorSize.height) / 2.0)), size: indicatorSize))
        originY += qrSide + 28.0

        transition.updateFrame(node: self.textNode, frame: CGRect(origin: CGPoint(x: floor((layout.size.width - textSize.width) / 2.0), y: originY), size: textSize))
    }
}

public final class NagramQrLoginController: ViewController {
    private var controllerNode: NagramQrLoginControllerNode {
        return self.displayNode as! NagramQrLoginControllerNode
    }

    private let sharedContext: SharedAccountContext
    private var account: UnauthorizedAccount
    private let presentationData: PresentationData
    private let accountUpdated: (UnauthorizedAccount) -> Void

    // Set once Telegram accepts the code, so the sequence controller only
    // dismisses this screen after it has served its purpose.
    public private(set) var hasBeenAccepted = false

    private let tokenDisposable = MetaDisposable()
    private let tokenEventsDisposable = MetaDisposable()
    private var validLayout: ContainerViewLayout?

    public init(sharedContext: SharedAccountContext, account: UnauthorizedAccount, presentationData: PresentationData, accountUpdated: @escaping (UnauthorizedAccount) -> Void) {
        self.sharedContext = sharedContext
        self.account = account
        self.presentationData = presentationData
        self.accountUpdated = accountUpdated

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: presentationData))

        self.statusBar.statusBarStyle = presentationData.theme.intro.statusBarStyle.style
        self.supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .portrait)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: presentationData.strings.Common_Cancel, style: .plain, target: self, action: #selector(self.cancelPressed))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.tokenDisposable.dispose()
        self.tokenEventsDisposable.dispose()
    }

    @objc private func cancelPressed() {
        self.dismiss()
    }

    override public func loadDisplayNode() {
        self.displayNode = NagramQrLoginControllerNode(presentationData: self.presentationData)
        self.displayNodeDidLoad()
        self.subscribeToTokenEvents()
        self.refreshToken()
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.validLayout = layout
        self.controllerNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
    }

    private func subscribeToTokenEvents() {
        let account = self.account
        self.tokenEventsDisposable.set((account.updateLoginTokenEvents
        |> deliverOnMainQueue).startStrict(next: { [weak self] _ in
            self?.refreshToken()
        }))
    }

    private func refreshToken() {
        let account = self.account
        let sharedContext = self.sharedContext
        let tokenSignal = sharedContext.activeAccountContexts
        |> castError(ExportAuthTransferTokenError.self)
        |> take(1)
        |> mapToSignal { activeAccountsAndInfo -> Signal<ExportAuthTransferTokenResult, ExportAuthTransferTokenError> in
            let (_, activeAccounts, _) = activeAccountsAndInfo
            let productionUserIds = activeAccounts.map({ $0.1.account }).filter({ !$0.testingEnvironment }).map({ $0.peerId.id })
            let testingUserIds = activeAccounts.map({ $0.1.account }).filter({ $0.testingEnvironment }).map({ $0.peerId.id })
            return TelegramEngineUnauthorized(account: account).auth.exportAuthTransferToken(
                accountManager: sharedContext.accountManager,
                otherAccountUserIds: account.testingEnvironment ? testingUserIds : productionUserIds,
                syncContacts: true
            )
        }

        self.tokenDisposable.set((tokenSignal
        |> deliverOnMainQueue).startStrict(next: { [weak self] result in
            guard let strongSelf = self else {
                return
            }
            switch result {
            case let .displayToken(token):
                var tokenString = token.value.base64EncodedString()
                tokenString = tokenString.replacingOccurrences(of: "+", with: "-")
                tokenString = tokenString.replacingOccurrences(of: "/", with: "_")
                strongSelf.displayCode(urlString: "tg://login?token=\(tokenString)")

                let timeout = max(5, token.validUntil - Int32(Date().timeIntervalSince1970))
                strongSelf.tokenDisposable.set((Signal<Never, NoError>.complete()
                |> delay(Double(timeout), queue: .mainQueue())).startStrict(completed: { [weak self] in
                    self?.refreshToken()
                }))
            case let .changeAccountAndRetry(account):
                strongSelf.tokenDisposable.set(nil)
                strongSelf.account = account
                strongSelf.accountUpdated(account)
                strongSelf.subscribeToTokenEvents()
                strongSelf.refreshToken()
            case .loggedIn, .passwordRequested:
                // Accepted. The sequence controller advances the flow and
                // dismisses this screen; until it does, say what is happening
                // rather than disappearing into the intro for several seconds.
                strongSelf.tokenDisposable.set(nil)
                strongSelf.hasBeenAccepted = true
                let language = strongSelf.presentationData.strings.baseLanguageCode
                strongSelf.controllerNode.setCompleting(
                    title: ngI18n("Nagram.QrLogin.Accepted.Title", language),
                    text: ngI18n("Nagram.QrLogin.Accepted.Text", language)
                )
                strongSelf.navigationItem.leftBarButtonItem = nil
                if let layout = strongSelf.validLayout {
                    strongSelf.containerLayoutUpdated(layout, transition: .immediate)
                }
            }
        }, error: { [weak self] _ in
            // A cold start often races the connection (CONNECTION_NOT_INITED).
            // Without this the screen keeps an empty square forever, because the
            // token request only ever runs once.
            guard let strongSelf = self else {
                return
            }
            let language = strongSelf.presentationData.strings.baseLanguageCode
            strongSelf.controllerNode.setCaption(ngI18n("Nagram.QrLogin.Retrying", language))
            strongSelf.tokenDisposable.set((Signal<Never, NoError>.complete()
            |> delay(3.0, queue: .mainQueue())).startStrict(completed: { [weak self] in
                self?.refreshToken()
            }))
        }))
    }

    private func displayCode(urlString: String) {
        let side: CGFloat = 260.0
        let _ = (qrCode(string: urlString, color: .black, backgroundColor: .white, icon: .none)
        |> deliverOnMainQueue).startStandalone(next: { [weak self] _, generate in
            guard let strongSelf = self, strongSelf.isNodeLoaded else {
                return
            }
            let context = generate(TransformImageArguments(corners: ImageCorners(), imageSize: CGSize(width: side, height: side), boundingSize: CGSize(width: side, height: side), intrinsicInsets: UIEdgeInsets()))
            if let image = context?.generateImage() {
                strongSelf.controllerNode.setCode(image)
            }
        })
    }
}
