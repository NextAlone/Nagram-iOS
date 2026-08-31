import Foundation
import UIKit
import Display
import NagramLoginUI
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import ProgressNavigationButtonNode
import AccountContext
import CountrySelectionUI
import PhoneNumberFormat
import DebugSettingsUI
import MessageUI
import AuthenticationServices

public final class AuthorizationSequencePhoneEntryController: ViewController, MFMailComposeViewControllerDelegate, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var controllerNode: AuthorizationSequencePhoneEntryControllerNode {
        return self.displayNode as! AuthorizationSequencePhoneEntryControllerNode
    }
    
    private var validLayout: ContainerViewLayout?
    
    private let sharedContext: SharedAccountContext
    private var account: UnauthorizedAccount?
    private let apiId: Int32
    private let apiHash: String
    private let isTestingEnvironment: Bool
    private let otherAccountPhoneNumbers: ((String, AccountRecordId, Bool)?, [(String, AccountRecordId, Bool)])
    private let network: Network
    private let presentationData: PresentationData
    private let openUrl: (String) -> Void
    
    private let back: () -> Void
    
    private var currentData: (Int32, String?, String)?
        
    var codeNode: ASDisplayNode {
        return self.controllerNode.codeNode
    }
    
    var numberNode: ASDisplayNode {
        return self.controllerNode.numberNode
    }
    
    var buttonNode: ASDisplayNode {
        return self.controllerNode.buttonNode
    }
    
    public var inProgress: Bool = false {
        didSet {
            self.updateNavigationItems()
            self.controllerNode.inProgress = self.inProgress
            self.confirmationController?.inProgress = self.inProgress
        }
    }
    public var loginWithNumber: ((String, Bool) -> Void)?
    public var loginWithPasskey: ((AuthorizationPasskeyData, Bool) -> Void)?
    var accountUpdated: ((UnauthorizedAccount) -> Void)?
    
    weak var confirmationController: PhoneConfirmationController?
    
    private let termsDisposable = MetaDisposable()
    
    private let hapticFeedback = HapticFeedback()
    
    public init(sharedContext: SharedAccountContext, account: UnauthorizedAccount?, countriesConfiguration: CountriesConfiguration? = nil, apiId: Int32, apiHash: String, isTestingEnvironment: Bool, otherAccountPhoneNumbers: ((String, AccountRecordId, Bool)?, [(String, AccountRecordId, Bool)]), network: Network, presentationData: PresentationData, openUrl: @escaping (String) -> Void, back: @escaping () -> Void) {
        self.sharedContext = sharedContext
        self.account = account
        self.apiId = apiId
        self.apiHash = apiHash
        self.isTestingEnvironment = isTestingEnvironment
        self.otherAccountPhoneNumbers = otherAccountPhoneNumbers
        self.network = network
        self.presentationData = presentationData
        self.openUrl = openUrl
        self.back = back
                
        super.init(navigationBarPresentationData: NavigationBarPresentationData(theme: AuthorizationSequenceController.navigationBarTheme(presentationData.theme), strings: NavigationBarStrings(presentationStrings: presentationData.strings)))
        
        self.supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .portrait)
        
        self.hasActiveInput = true
        
        self.statusBar.statusBarStyle = presentationData.theme.intro.statusBarStyle.style
        self.attemptNavigation = { _ in
            return false
        }
        self.navigationBar?.backPressed = {
            back()
        }
        
        if !otherAccountPhoneNumbers.1.isEmpty {
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "___close", style: .plain, target: self, action: #selector(self.cancelPressed))
        }
        
        if let countriesConfiguration {
            AuthorizationSequenceCountrySelectionController.setupCountryCodes(countries: countriesConfiguration.countries, codesByPrefix: countriesConfiguration.countriesByPrefix)
        }
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.termsDisposable.dispose()
    }
    
    // MARK: NAGRAM — 添加账号时也要有账号入口。这条路径没有 splash 屏，
    // 手机号页就是导航栈根，所以按钮放在右上角（宽屏下上游不占用该位置；
    // 窄屏时上游的“下一步”会覆盖它）。
    private var nagramLoginButton: NagramLoginOptionsButton?
    private var nagramLoginOptionsPressed: (() -> Void)?
    private var nagramPendingBadgeCount: Int = 0
    // Recounted on every appearance: the keychain can gain an account while this
    // screen is up (iCloud sync) and loses one whenever the user restores it.
    var nagramRefreshLoginBadge: (() -> Void)?

    // MARK: NAGRAM — 点按打开菜单。
    func setNagramLoginOptions(accessibilityLabel: String, action: @escaping () -> Void) {
        self.nagramLoginOptionsPressed = action
        let button = NagramLoginOptionsButton(
            icon: NagramLoginOptionsButton.defaultIcon(color: self.presentationData.theme.list.itemAccentColor),
            accessibilityLabel: accessibilityLabel
        )
        button.accessibilityIdentifier = "Auth.PhoneEntry.NagramAccountButton"
        button.addTarget(self, action: #selector(self.nagramLoginButtonPressed), for: .touchUpInside)
        button.setBadgeCount(self.nagramPendingBadgeCount)
        self.nagramLoginButton = button
    }

    // MARK: NAGRAM — 用浮层按钮而不是 UIBarButtonItem：这一屏的导航栏是透明且通常没有
    // 其他按钮，栏内按钮不会显示；而且在构造阶段动 navigationItem 会提前触发 view
    // 加载，把 splash 的过渡动画卡在中途。挂载与摆位都放到布局阶段。
    private func nagramLayoutLoginButton(_ layout: ContainerViewLayout) {
        guard let button = self.nagramLoginButton, self.isNodeLoaded else {
            return
        }
        if button.superview == nil {
            self.displayNode.view.addSubview(button)
        }
        let size = NagramLoginOptionsButton.preferredSize
        let topInset = (layout.statusBarHeight ?? 20.0) + 4.0
        let rightInset = max(layout.safeInsets.right, 8.0)
        button.frame = CGRect(origin: CGPoint(x: layout.size.width - rightInset - size.width, y: topInset), size: size)
        self.displayNode.view.bringSubviewToFront(button)
    }

    // MARK: NAGRAM
    func setNagramLoginBadgeCount(_ count: Int) {
        self.nagramPendingBadgeCount = count
        self.nagramLoginButton?.setBadgeCount(count)
    }

    // MARK: NAGRAM
    @objc private func nagramLoginButtonPressed() {
        self.nagramLoginOptionsPressed?()
    }

    @objc private func cancelPressed() {
        self.back()
    }
    
    func updateNavigationItems() {
        guard let layout = self.validLayout, layout.size.width < 360.0 else {
            return
        }
                
        if self.inProgress {
            let item = UIBarButtonItem(customDisplayNode: ProgressNavigationButtonNode(color: self.presentationData.theme.rootController.navigationBar.accentTextColor))
            self.navigationItem.rightBarButtonItem = item
        } else {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Next, style: .done, target: self, action: #selector(self.nextPressed))
        }
    }
    
    public func updateData(countryCode: Int32, countryName: String?, number: String) {
        self.currentData = (countryCode, countryName, number)
        if self.isNodeLoaded {
            self.controllerNode.codeAndNumber = (countryCode, countryName, number)
        }
    }
    
    private var shouldAnimateIn = false
    private var transitionInArguments: (buttonFrame: CGRect, buttonTitle: String, animationSnapshot: UIView, textSnapshot: UIView)?
    
    func animateWithSplashController(_ controller: AuthorizationSequenceSplashController) {
        self.shouldAnimateIn = true
        
        if let animationSnapshot = controller.animationSnapshot, let textSnapshot = controller.textSnaphot {
            self.transitionInArguments = (controller.buttonFrame, controller.buttonTitle, animationSnapshot, textSnapshot)
        }
    }
    
    override public func loadDisplayNode() {
        self.displayNode = AuthorizationSequencePhoneEntryControllerNode(sharedContext: self.sharedContext, account: self.account, strings: self.presentationData.strings, theme: self.presentationData.theme, debugAction: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.view.endEditing(true)
            self?.present(debugController(sharedContext: strongSelf.sharedContext, context: nil, modal: true), in: .window(.root), with: ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
        }, hasOtherAccounts: self.otherAccountPhoneNumbers.0 != nil)
        self.controllerNode.accountUpdated = { [weak self] account in
            guard let strongSelf = self else {
                return
            }
            strongSelf.account = account
            strongSelf.accountUpdated?(account)
        }
        self.controllerNode.retryPasskey = { [weak self] in
            guard let self else {
                return
            }
            self.loadAndPresentPasskey(force: true)
        }
        
        if let (code, name, number) = self.currentData {
            self.controllerNode.codeAndNumber = (code, name, number)
        }
        self.displayNodeDidLoad()
        
        self.controllerNode.view.disableAutomaticKeyboardHandling = [.forward, .backward]
        
        self.controllerNode.selectCountryCode = { [weak self] in
            if let strongSelf = self {
                let controller = AuthorizationSequenceCountrySelectionController(strings: strongSelf.presentationData.strings, theme: strongSelf.presentationData.theme, glass: true)
                controller.completeWithCountryCode = { code, name in
                    if let strongSelf = self, let currentData = strongSelf.currentData {
                        strongSelf.updateData(countryCode: Int32(code), countryName: name, number: currentData.2)
                        strongSelf.controllerNode.activateInput()
                    }
                }
                controller.dismissed = { 
                    self?.controllerNode.activateInput()
                }
                strongSelf.push(controller)
            }
        }
        self.controllerNode.checkPhone = { [weak self] in
            self?.nextPressed()
        }
        
        if let account = self.account {
            loadServerCountryCodes(accountManager: sharedContext.accountManager, engine: TelegramEngineUnauthorized(account: account), completion: { [weak self] in
                if let strongSelf = self {
                    strongSelf.controllerNode.updateCountryCode()
                }
            })
        } else {
            self.controllerNode.updateCountryCode()
        }
        
        self.loadAndPresentPasskey(force: false)
    }
    
    private func loadAndPresentPasskey(force: Bool) {
        if #available(iOS 16.0, *) {
            Task { @MainActor [weak self] in
                guard let self, let account = self.account else {
                    return
                }
                
                let decodeBase64: (String) -> Data? = { string in
                    var string = string.replacingOccurrences(of: "-", with: "+")
                        .replacingOccurrences(of: "_", with: "/")
                    while string.count % 4 != 0 {
                        string.append("=")
                    }
                    return Data(base64Encoded: string)
                }
                
                let engine = TelegramEngineUnauthorized(account: account)
                let passkeyDataString = await engine.auth.requestPasskeyLoginData(apiId: self.apiId, apiHash: self.apiHash).get()
                guard let passkeyDataString, let passkeyData = passkeyDataString.data(using: .utf8) else {
                    return
                }
                guard let params = try? JSONSerialization.jsonObject(with: passkeyData) as? [String: Any] else {
                    return
                }
                guard let pkDict = params["publicKey"] as? [String: Any] else {
                    return
                }
                guard let relyingPartyIdentifier = pkDict["rpId"] as? String else {
                    return
                }
                guard let challengeBase64 = pkDict["challenge"] as? String else {
                    return
                }
                guard let challengeData = decodeBase64(challengeBase64) else {
                    return
                }
                
                let platformProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)
                let platformKeyRequest = platformProvider.createCredentialAssertionRequest(challenge: challengeData)
                let authController = ASAuthorizationController(authorizationRequests: [platformKeyRequest])
                authController.delegate = self
                authController.presentationContextProvider = self
                if force {
                    authController.performRequests()
                } else {
                    authController.performRequests(options: [.preferImmediatelyAvailableCredentials])
                }
            }
        }
    }
    
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor [weak self] in
            guard let self, let account = self.account else {
                return
            }
            
            let encodeBase64URL: (Data) -> String = { data in
                var string = data.base64EncodedString()
                string = string
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                string = string.replacingOccurrences(of: "=", with: "")
                return string
            }
            
            if #available(iOS 17.0, *) {
                if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
                    guard let clientData = String(data: credential.rawClientDataJSON, encoding: .utf8) else {
                        return
                    }
                    guard let userHandle = String(data: credential.userID, encoding: .utf8) else {
                        return
                    }
                    let passkey = AuthorizationPasskeyData(
                        id: encodeBase64URL(credential.credentialID),
                        clientData: clientData,
                        authenticatorData: credential.rawAuthenticatorData,
                        signature: credential.signature,
                        userHandle: userHandle
                    )
                    self.loginWithPasskey?(passkey, self.controllerNode.syncContacts)
                    
                    /*if let clientData = String(data: credential.rawClientDataJSON, encoding: .utf8), let attestationObject = credential.rawAttestationObject {
                        let passkey = await component.context.engine.auth.requestCreatePasskey(id: encodeBase64URL(credential.credentialID), clientData: clientData, attestationObject: attestationObject).get()
                        if let passkey {
                            if self.passkeysData == nil {
                                self.passkeysData = []
                                self.passkeysData?.insert(passkey, at: 0)
                            }
                            self.state?.updated(transition: .immediate)
                        }
                    }*/
                    let _ = account
                    let _ = credential
                }
            }
        }
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        if (error as NSError).domain == "com.apple.AuthenticationServices.AuthorizationError" && (error as NSError).code == 1001 {
            self.controllerNode.updateDisplayPasskeyLoginOption()
            if let validLayout = self.validLayout {
                self.containerLayoutUpdated(validLayout, transition: .immediate)
            }
        }
    }
    
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = self.view.window?.windowScene else {
            preconditionFailure()
        }
        return ASPresentationAnchor(windowScene: windowScene)
    }
    
    public func updateCountryCode() {
        self.controllerNode.updateCountryCode()
    }
    
    private var animatingIn = false
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // MARK: NAGRAM
        self.nagramRefreshLoginBadge?()
        
        if self.shouldAnimateIn {
            self.animatingIn = true
            if let (buttonFrame, buttonTitle, animationSnapshot, textSnapshot) = self.transitionInArguments {
                self.controllerNode.willAnimateIn(buttonFrame: buttonFrame, buttonTitle: buttonTitle, animationSnapshot: animationSnapshot, textSnapshot: textSnapshot)
            }
            Queue.mainQueue().justDispatch {
                self.controllerNode.activateInput()
            }
        } else {
            self.controllerNode.activateInput()
        }
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !self.animatingIn {
            self.controllerNode.activateInput()
        }

        // MARK: NAGRAM — 见 nagramRunPendingTransitionIn 的说明：键盘不出现时兜底。
        Queue.mainQueue().after(1.0) { [weak self] in
            self?.nagramRunPendingTransitionIn()
        }
    }

    // MARK: NAGRAM — 播放来自 splash 的入场动画。
    //
    // 原本这个动画只在软键盘出现（layout.inputHeight > 0）时才触发。viewWillAppear
    // 里的 willAnimateIn 已经把 splash 的截图贴到了本屏上，所以键盘一旦不出现，
    // 截图就会一直留着，看起来像点了「Start with Nagram」之后卡死——模拟器连着
    // 硬件键盘时必现。这里把触发点收敛到一处，并在 viewDidAppear 之后兜底调用，
    // 保证动画一定会跑完；键盘正常出现时仍由 containerLayoutUpdated 先触发。
    private func nagramRunPendingTransitionIn() {
        guard self.isNodeLoaded, self.shouldAnimateIn else {
            return
        }
        guard let (buttonFrame, buttonTitle, animationSnapshot, textSnapshot) = self.transitionInArguments else {
            return
        }
        self.shouldAnimateIn = false
        self.controllerNode.animateIn(buttonFrame: buttonFrame, buttonTitle: buttonTitle, animationSnapshot: animationSnapshot, textSnapshot: textSnapshot)
    }
    
    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if let confirmationController = self.confirmationController {
            confirmationController.transitionOut()
        }
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        let hadLayout = self.validLayout != nil
        self.validLayout = layout

        // MARK: NAGRAM
        self.nagramLayoutLoginButton(layout)
        
        if !hadLayout {
            self.updateNavigationItems()
        }
    
        self.controllerNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
        
        if let inputHeight = layout.inputHeight, inputHeight > 0.0 {
            self.nagramRunPendingTransitionIn()
        }
    }
    
    public func dismissConfirmation() {
        self.confirmationController?.dismissAnimated()
        self.confirmationController = nil
    }
    
    @objc func nextPressed() {
        guard self.confirmationController == nil else {
            return
        }
        let (_, _, number) = self.controllerNode.codeAndNumber
        if !number.isEmpty {
            let logInNumber = cleanPhoneNumber(self.controllerNode.currentNumber, removePlus: true)
            var existing: (String, AccountRecordId)?
            for (number, id, isTestingEnvironment) in self.otherAccountPhoneNumbers.1 {
                if isTestingEnvironment == self.isTestingEnvironment && cleanPhoneNumber(number, removePlus: true) == logInNumber {
                    existing = (number, id)
                }
            }
            
            if let (_, id) = existing {
                var actions: [TextAlertAction] = []
                if let (current, _, _) = self.otherAccountPhoneNumbers.0, logInNumber != cleanPhoneNumber(current, removePlus: true) {
                    actions.append(TextAlertAction(type: .genericAction, title: self.presentationData.strings.Login_PhoneNumberAlreadyAuthorizedSwitch, action: { [weak self] in
                        self?.sharedContext.switchToAccount(id: id, fromSettingsController: nil, withChatListController: nil)
                        self?.back()
                    }))
                }
                actions.append(TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_OK, action: {}))
                self.present(textAlertController(sharedContext: self.sharedContext, title: nil, text: self.presentationData.strings.Login_PhoneNumberAlreadyAuthorized, actions: actions), in: .window(.root))
            } else {
                if let validLayout = self.validLayout, validLayout.size.width > 320.0 {
                    let (code, formattedNumber) = self.controllerNode.formattedCodeAndNumber

                    let confirmationController = PhoneConfirmationController(theme: self.presentationData.theme, strings: self.presentationData.strings, code: code, number: formattedNumber, sourceController: self)
                    confirmationController.proceed = { [weak self] in
                        if let strongSelf = self {
                            strongSelf.loginWithNumber?(strongSelf.controllerNode.currentNumber, strongSelf.controllerNode.syncContacts)
                        }
                    }
                    (self.navigationController as? NavigationController)?.presentOverlay(controller: confirmationController, inGlobal: true, blockInteraction: true)
                    self.confirmationController = confirmationController
                } else {
                    var actions: [TextAlertAction] = []
                    actions.append(TextAlertAction(type: .genericAction, title: self.presentationData.strings.Login_Edit, action: {}))
                    actions.append(TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Login_Yes, action: { [weak self] in
                        if let strongSelf = self {
                            strongSelf.loginWithNumber?(strongSelf.controllerNode.currentNumber, strongSelf.controllerNode.syncContacts)
                        }
                    }))
                    self.present(textAlertController(sharedContext: self.sharedContext, title: logInNumber, text: self.presentationData.strings.Login_PhoneNumberConfirmation, actions: actions), in: .window(.root))
                }
            }
        } else {
            self.hapticFeedback.error()
            self.controllerNode.animateError()
        }
    }
    
    public func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true, completion: nil)
    }
}
