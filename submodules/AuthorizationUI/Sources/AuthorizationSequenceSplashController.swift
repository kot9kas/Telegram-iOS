import Foundation
import UIKit
import Display
import AsyncDisplayKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramPresentationData
import SolidRoundedButtonNode
import AnimatedStickerNode
import TelegramAnimatedStickerNode

public final class AuthorizationSequenceSplashController: ViewController {
    private var controllerNode: AuthorizationSequenceSplashControllerNode {
        return self.displayNode as! AuthorizationSequenceSplashControllerNode
    }
    
    private let accountManager: AccountManager<TelegramAccountManagerTypes>
    private let account: UnauthorizedAccount
    private let theme: PresentationTheme
    
    private var validLayout: ContainerViewLayout?
    
    var nextPressed: ((PresentationStrings?) -> Void)?
    
    private let suggestedLocalization = Promise<SuggestedLocalizationInfo?>()
    private let activateLocalizationDisposable = MetaDisposable()
    
    private let animationNode: AnimatedStickerNode
    private let startButton: SolidRoundedButtonNode
    
    init(accountManager: AccountManager<TelegramAccountManagerTypes>, account: UnauthorizedAccount, theme: PresentationTheme) {
        self.accountManager = accountManager
        self.account = account
        self.theme = theme
        
        self.suggestedLocalization.set(.single(nil)
        |> then(TelegramEngineUnauthorized(account: self.account).localization.currentlySuggestedLocalization(extractKeys: ["Login.ContinueWithLocalization"])))
        
        self.animationNode = DefaultAnimatedStickerNodeImpl()
        self.animationNode.setup(source: AnimatedStickerNodeLocalFileSource(name: "IntroSplash"), width: 640, height: 640, playbackMode: .loop, mode: .direct(cachePathPrefix: nil))
        
        self.startButton = SolidRoundedButtonNode(title: "Start Messaging", theme: SolidRoundedButtonTheme(theme: theme), glass: false, height: 50.0, cornerRadius: 50.0 * 0.5, isShimmering: true)
        self.startButton.accessibilityIdentifier = "Auth.Welcome.StartButton"

        super.init(navigationBarPresentationData: nil)
        
        self._hasGlassStyle = true
        
        self.supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .portrait)
        
        self.statusBar.statusBarStyle = theme.intro.statusBarStyle.style
        
        self.startButton.pressed = { [weak self] in
            self?.activateLocalization("en")
        }
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.activateLocalizationDisposable.dispose()
    }
    
    public override func loadDisplayNode() {
        self.displayNode = AuthorizationSequenceSplashControllerNode(theme: self.theme)
        self.displayNodeDidLoad()
        
        self.displayNode.addSubnode(self.animationNode)
        self.displayNode.addSubnode(self.startButton)
        
        self.animationNode.visibility = true
    }
    
    func animateIn() {
        self.animationNode.alpha = 0.0
        self.startButton.alpha = 0.0
        UIView.animate(withDuration: 0.4) {
            self.animationNode.alpha = 1.0
            self.startButton.alpha = 1.0
        }
    }
    
    var buttonFrame: CGRect {
        return self.startButton.frame
    }
    
    var buttonTitle: String {
        return self.startButton.title ?? ""
    }
    
    var animationSnapshot: UIView? {
        return self.animationNode.view.snapshotView(afterScreenUpdates: false)
    }
    
    var textSnaphot: UIView? {
        return UIView(frame: CGRect(origin: .zero, size: CGSize(width: 1.0, height: 1.0)))
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
    public override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        self.validLayout = layout
        
        self.controllerNode.containerLayoutUpdated(layout, navigationBarHeight: 0.0, transition: transition)
        
        let animationSize = CGSize(width: 333.0, height: 333.0)
        let buttonWidth = min(layout.size.width - 48.0, 320.0)
        let _ = self.startButton.updateLayout(width: buttonWidth, transition: transition)
        
        let totalHeight = animationSize.height + 60.0 + 50.0
        let topOffset = floorToScreenPixels((layout.size.height - totalHeight) / 2.0) - layout.safeInsets.top * 0.3
        
        let animationFrame = CGRect(
            origin: CGPoint(
                x: floorToScreenPixels((layout.size.width - animationSize.width) / 2.0),
                y: topOffset
            ),
            size: animationSize
        )
        transition.updateFrame(node: self.animationNode, frame: animationFrame)
        self.animationNode.updateLayout(size: animationSize)
        
        let buttonFrame = CGRect(
            origin: CGPoint(
                x: floorToScreenPixels((layout.size.width - buttonWidth) / 2.0),
                y: layout.size.height - layout.intrinsicInsets.bottom - 50.0 - 48.0
            ),
            size: CGSize(width: buttonWidth, height: 50.0)
        )
        transition.updateFrame(node: self.startButton, frame: buttonFrame)
    }
    
    private func activateLocalization(_ code: String) {
        let currentCode = self.accountManager.transaction { transaction -> String in
            if let current = transaction.getSharedData(SharedDataKeys.localizationSettings)?.get(LocalizationSettings.self) {
                return current.primaryComponent.languageCode
            } else {
                return "en"
            }
        }
        let suggestedCode = self.suggestedLocalization.get()
        |> map { localization -> String? in
            return localization?.availableLocalizations.first?.languageCode
        }
        
        let _ = (combineLatest(currentCode, suggestedCode)
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] currentCode, suggestedCode in
            guard let strongSelf = self else {
                return
            }
            
            if let suggestedCode = suggestedCode {
                _ = TelegramEngineUnauthorized(account: strongSelf.account).localization.markSuggestedLocalizationAsSeenInteractively(languageCode: suggestedCode).start()
            }
            
            if currentCode == code {
                strongSelf.pressNext(strings: nil)
                return
            }
            
            strongSelf.startButton.alpha = 0.6
            let accountManager = strongSelf.accountManager
            
            strongSelf.activateLocalizationDisposable.set(TelegramEngineUnauthorized(account: strongSelf.account).localization.downloadAndApplyLocalization(accountManager: accountManager, languageCode: code).start(completed: {
                let _ = (accountManager.transaction { transaction -> PresentationStrings? in
                    let localizationSettings: LocalizationSettings?
                    if let current = transaction.getSharedData(SharedDataKeys.localizationSettings)?.get(LocalizationSettings.self) {
                        localizationSettings = current
                    } else {
                        localizationSettings = nil
                    }
                    let stringsValue: PresentationStrings
                    if let localizationSettings = localizationSettings {
                        stringsValue = PresentationStrings(primaryComponent: PresentationStrings.Component(languageCode: localizationSettings.primaryComponent.languageCode, localizedName: localizationSettings.primaryComponent.localizedName, pluralizationRulesCode: localizationSettings.primaryComponent.customPluralizationCode, dict: dictFromLocalization(localizationSettings.primaryComponent.localization)), secondaryComponent: localizationSettings.secondaryComponent.flatMap({ PresentationStrings.Component(languageCode: $0.languageCode, localizedName: $0.localizedName, pluralizationRulesCode: $0.customPluralizationCode, dict: dictFromLocalization($0.localization)) }), groupingSeparator: "")
                    } else {
                        stringsValue = defaultPresentationStrings
                    }
                    return stringsValue
                }
                |> deliverOnMainQueue).start(next: { strings in
                    self?.startButton.alpha = 1.0
                    self?.pressNext(strings: strings)
                })
            }))
        })
    }
    
    private func pressNext(strings: PresentationStrings?) {
        if let navigationController = self.navigationController, navigationController.viewControllers.last === self {
            self.nextPressed?(strings)
        }
    }
}
