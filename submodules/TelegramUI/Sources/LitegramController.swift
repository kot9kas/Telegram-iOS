import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import AppBundle
import TabBarUI
import Litegram
import AnimatedStickerNode
import TelegramAnimatedStickerNode

public final class LitegramController: ViewController {
    private let context: AccountContext
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    private var proxySettingsDisposable: Disposable?
    private var connectionStatusDisposable: Disposable?
    
    private var currentProxySettings: ProxySettings?
    private var currentConnectionStatus: ConnectionStatus = .waitingForNetwork
    
    private var scrollNode: ASScrollNode?
    
    private var headerNode: ASDisplayNode?
    private var headerAnimationNode: AnimatedStickerNode?
    private var headerTitleNode: ASTextNode?
    private var headerSubtitleNode: ASTextNode?
    private var statusDotNode: ASDisplayNode?
    private var statusTextNode: ASTextNode?
    
    private var serverRowNode: ASDisplayNode?
    private var serverTitleNode: ASTextNode?
    private var serverValueNode: ASTextNode?
    private var planRowNode: ASDisplayNode?
    private var planTitleNode: ASTextNode?
    private var planValueNode: ASTextNode?
    
    private var actionButtonNode: ASButtonNode?
    private var actionButtonGradient: CAGradientLayer?
    
    private var featuresContainerNode: ASDisplayNode?
    private var featureRowNodes: [ASDisplayNode] = []
    private var featureDotNodes: [ASDisplayNode] = []
    private var featureLabelNodes: [ASTextNode] = []
    private var featureSepNodes: [ASDisplayNode] = []
    
    private var isConnecting = false
    
    private static let featureColors: [UIColor] = [
        UIColor(rgb: 0xef6922),
        UIColor(rgb: 0xe54937),
        UIColor(rgb: 0xab4ac4),
        UIColor(rgb: 0x676bff),
        UIColor(rgb: 0x3eb26d)
    ]
    
    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        self.navigationItem.title = "Litegram"
        
        self.tabBarItem.title = "Litegram"
        let icon = UIImage(bundleImageName: "Chat List/Tabs/IconLitegram")
        self.tabBarItem.image = icon
        self.tabBarItem.selectedImage = icon
        if !self.presentationData.reduceMotion {
            self.tabBarItem.animationName = "TabLitegram"
            self.tabBarItem.animationOffset = CGPoint(x: 0.0, y: UIScreenPixel)
        }
        
        self.presentationDataDisposable = (context.sharedContext.presentationData
            |> deliverOnMainQueue).startStrict(next: { [weak self] presentationData in
                guard let self = self else { return }
                let previousTheme = self.presentationData.theme
                self.presentationData = presentationData
                
                if previousTheme !== presentationData.theme {
                    self.updateTheme()
                }
                
                self.tabBarItem.title = "Litegram"
                if !presentationData.reduceMotion {
                    self.tabBarItem.animationName = "TabLitegram"
                    self.tabBarItem.animationOffset = CGPoint(x: 0.0, y: UIScreenPixel)
                } else {
                    self.tabBarItem.animationName = nil
                }
            })
        
        self.proxySettingsDisposable = (context.sharedContext.accountManager.sharedData(keys: [SharedDataKeys.proxySettings])
            |> deliverOnMainQueue).startStrict(next: { [weak self] sharedData in
                guard let self = self else { return }
                let settings = sharedData.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? ProxySettings.defaultSettings
                self.currentProxySettings = settings
                self.updateUI()
            })
        
        self.connectionStatusDisposable = (context.account.network.connectionStatus
            |> deliverOnMainQueue).startStrict(next: { [weak self] status in
                guard let self = self else { return }
                self.currentConnectionStatus = status
                self.updateUI()
            })
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.presentationDataDisposable?.dispose()
        self.proxySettingsDisposable?.dispose()
        self.connectionStatusDisposable?.dispose()
    }
    
    private func updateTheme() {
        self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: self.presentationData), transition: .immediate)
        if self.isNodeLoaded {
            self.updateColors()
        }
    }
    
    override public func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
        
        let scrollNode = ASScrollNode()
        scrollNode.view.alwaysBounceVertical = true
        self.displayNode.addSubnode(scrollNode)
        self.scrollNode = scrollNode
        
        setupNodes()
        
        self.updateTabBarSearchState(ViewController.TabBarSearchState(isActive: false), transition: .immediate)
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        let navBarHeight = self.navigationLayout(layout: layout).navigationFrame.maxY
        let bottomInset = layout.intrinsicInsets.bottom
        
        if let scrollNode = self.scrollNode {
            let scrollFrame = CGRect(x: 0, y: navBarHeight, width: layout.size.width, height: layout.size.height - navBarHeight)
            transition.updateFrame(node: scrollNode, frame: scrollFrame)
        }
        
        layoutNodes(width: layout.size.width, bottomInset: bottomInset)
    }
    
    private func setupNodes() {
        let theme = self.presentationData.theme
        
        // MARK: Header with gradient + Lottie animation
        let header = ASDisplayNode()
        header.clipsToBounds = true
        header.cornerRadius = 16
        scrollNode?.addSubnode(header)
        self.headerNode = header
        
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor(rgb: 0x6a94ff).cgColor,
            UIColor(rgb: 0x9472fd).cgColor,
            UIColor(rgb: 0xe26bd3).cgColor
        ]
        gradientLayer.locations = [0.0, 0.5, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        header.layer.insertSublayer(gradientLayer, at: 0)
        
        let animationNode = DefaultAnimatedStickerNodeImpl()
        animationNode.setup(source: AnimatedStickerNodeLocalFileSource(name: "TabLitegram"), width: 240, height: 240, playbackMode: .loop, mode: .direct(cachePathPrefix: nil))
        animationNode.visibility = true
        animationNode.setOverlayColor(.white, replace: true, animated: false)
        header.addSubnode(animationNode)
        self.headerAnimationNode = animationNode
        
        let headerTitle = ASTextNode()
        headerTitle.attributedText = NSAttributedString(string: "Litegram", attributes: [
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: UIColor.white
        ])
        header.addSubnode(headerTitle)
        self.headerTitleNode = headerTitle
        
        let headerSubtitle = ASTextNode()
        headerSubtitle.attributedText = NSAttributedString(string: "Secure proxy for unrestricted access", attributes: [
            .font: UIFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: UIColor.white.withAlphaComponent(0.85)
        ])
        headerSubtitle.maximumNumberOfLines = 2
        header.addSubnode(headerSubtitle)
        self.headerSubtitleNode = headerSubtitle
        
        // MARK: Status row
        let statusDot = ASDisplayNode()
        statusDot.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        statusDot.cornerRadius = 5
        header.addSubnode(statusDot)
        self.statusDotNode = statusDot
        
        let statusText = ASTextNode()
        statusText.attributedText = NSAttributedString(string: "Disconnected", attributes: [
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: UIColor.white
        ])
        header.addSubnode(statusText)
        self.statusTextNode = statusText
        
        // MARK: Info rows
        let serverRow = ASDisplayNode()
        serverRow.backgroundColor = theme.list.itemBlocksBackgroundColor
        serverRow.cornerRadius = 12
        scrollNode?.addSubnode(serverRow)
        self.serverRowNode = serverRow
        
        let serverTitle = ASTextNode()
        serverTitle.attributedText = NSAttributedString(string: "Server", attributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: theme.list.itemPrimaryTextColor])
        serverRow.addSubnode(serverTitle)
        self.serverTitleNode = serverTitle
        
        let serverValue = ASTextNode()
        serverValue.attributedText = NSAttributedString(string: "Not connected", attributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: theme.list.itemSecondaryTextColor])
        serverRow.addSubnode(serverValue)
        self.serverValueNode = serverValue
        
        let planRow = ASDisplayNode()
        planRow.backgroundColor = theme.list.itemBlocksBackgroundColor
        planRow.cornerRadius = 12
        scrollNode?.addSubnode(planRow)
        self.planRowNode = planRow
        
        let planTitle = ASTextNode()
        planTitle.attributedText = NSAttributedString(string: "Plan", attributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: theme.list.itemPrimaryTextColor])
        planRow.addSubnode(planTitle)
        self.planTitleNode = planTitle
        
        let planValue = ASTextNode()
        planValue.attributedText = NSAttributedString(string: "Free", attributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: theme.list.itemSecondaryTextColor])
        planRow.addSubnode(planValue)
        self.planValueNode = planValue
        
        // MARK: Action button with gradient
        let button = ASButtonNode()
        button.setTitle("Connect", with: UIFont.systemFont(ofSize: 17, weight: .semibold), with: .white, for: .normal)
        button.cornerRadius = 12
        button.clipsToBounds = true
        button.addTarget(self, action: #selector(actionButtonTapped), forControlEvents: .touchUpInside)
        scrollNode?.addSubnode(button)
        self.actionButtonNode = button
        
        let btnGradient = CAGradientLayer()
        btnGradient.colors = [
            UIColor(rgb: 0x6a94ff).cgColor,
            UIColor(rgb: 0x9472fd).cgColor,
            UIColor(rgb: 0xe26bd3).cgColor
        ]
        btnGradient.startPoint = CGPoint(x: 0, y: 0.5)
        btnGradient.endPoint = CGPoint(x: 1, y: 0.5)
        button.layer.insertSublayer(btnGradient, at: 0)
        self.actionButtonGradient = btnGradient
        
        // MARK: Features
        let featuresContainer = ASDisplayNode()
        featuresContainer.backgroundColor = theme.list.itemBlocksBackgroundColor
        featuresContainer.cornerRadius = 12
        featuresContainer.clipsToBounds = true
        scrollNode?.addSubnode(featuresContainer)
        self.featuresContainerNode = featuresContainer
        
        let features = [
            "Access blocked content",
            "Enhanced privacy protection",
            "Fast and stable connection",
            "No speed limitations",
            "Auto-reconnect support"
        ]
        
        for (i, text) in features.enumerated() {
            let row = ASDisplayNode()
            featuresContainer.addSubnode(row)
            self.featureRowNodes.append(row)
            
            let dot = ASDisplayNode()
            let color = Self.featureColors[i % Self.featureColors.count]
            dot.backgroundColor = color
            dot.cornerRadius = 4
            row.addSubnode(dot)
            self.featureDotNodes.append(dot)
            
            let label = ASTextNode()
            label.attributedText = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: theme.list.itemPrimaryTextColor])
            row.addSubnode(label)
            self.featureLabelNodes.append(label)
            
            if i < features.count - 1 {
                let sep = ASDisplayNode()
                sep.backgroundColor = theme.list.itemBlocksSeparatorColor
                featuresContainer.addSubnode(sep)
                self.featureSepNodes.append(sep)
            }
        }
        
        updateUI()
    }
    
    private func updateColors() {
        let theme = self.presentationData.theme
        self.displayNode.backgroundColor = theme.list.blocksBackgroundColor
        self.serverRowNode?.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.planRowNode?.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.featuresContainerNode?.backgroundColor = theme.list.itemBlocksBackgroundColor
    }
    
    private func layoutNodes(width: CGFloat, bottomInset: CGFloat) {
        let padding: CGFloat = 16
        let contentWidth = width - padding * 2
        var y: CGFloat = 12
        
        let headerHeight: CGFloat = 220
        if let header = self.headerNode {
            let headerFrame = CGRect(x: padding, y: y, width: contentWidth, height: headerHeight)
            header.frame = headerFrame
            if let gradient = header.layer.sublayers?.first as? CAGradientLayer {
                gradient.frame = CGRect(origin: .zero, size: headerFrame.size)
            }
            
            let animSize: CGFloat = 80
            self.headerAnimationNode?.frame = CGRect(x: (contentWidth - animSize) / 2, y: 16, width: animSize, height: animSize)
            self.headerAnimationNode?.updateLayout(size: CGSize(width: animSize, height: animSize))
            
            let titleY: CGFloat = 16 + animSize + 8
            self.headerTitleNode?.frame = CGRect(x: 0, y: titleY, width: contentWidth, height: 34)
            self.headerTitleNode?.textAlignment = .center
            
            let subtitleY = titleY + 34
            self.headerSubtitleNode?.frame = CGRect(x: 20, y: subtitleY, width: contentWidth - 40, height: 22)
            self.headerSubtitleNode?.textAlignment = .center
            
            let statusY = subtitleY + 28
            self.statusDotNode?.frame = CGRect(x: contentWidth / 2 - 50, y: statusY + 5, width: 10, height: 10)
            self.statusTextNode?.frame = CGRect(x: contentWidth / 2 - 35, y: statusY, width: contentWidth / 2 + 35, height: 20)
            
            y += headerHeight + 16
        }
        
        let rowH: CGFloat = 48
        if let serverRow = self.serverRowNode {
            serverRow.frame = CGRect(x: padding, y: y, width: contentWidth, height: rowH)
            self.serverTitleNode?.frame = CGRect(x: 16, y: 0, width: contentWidth * 0.35, height: rowH)
            self.serverValueNode?.frame = CGRect(x: contentWidth * 0.35, y: 0, width: contentWidth * 0.65 - 16, height: rowH)
            y += rowH + 8
        }
        
        if let planRow = self.planRowNode {
            planRow.frame = CGRect(x: padding, y: y, width: contentWidth, height: rowH)
            self.planTitleNode?.frame = CGRect(x: 16, y: 0, width: contentWidth * 0.35, height: rowH)
            self.planValueNode?.frame = CGRect(x: contentWidth * 0.35, y: 0, width: contentWidth * 0.65 - 16, height: rowH)
            y += rowH + 16
        }
        
        let buttonH: CGFloat = 50
        if let button = self.actionButtonNode {
            button.frame = CGRect(x: padding, y: y, width: contentWidth, height: buttonH)
            self.actionButtonGradient?.frame = CGRect(x: 0, y: 0, width: contentWidth, height: buttonH)
            y += buttonH + 16
        }
        
        if let _ = self.featuresContainerNode {
            let featureRowH: CGFloat = 48
            let sepH: CGFloat = 0.5
            let count = featureRowNodes.count
            let totalH = CGFloat(count) * featureRowH + CGFloat(featureSepNodes.count) * sepH
            self.featuresContainerNode?.frame = CGRect(x: padding, y: y, width: contentWidth, height: totalH)
            
            var fy: CGFloat = 0
            for i in 0..<count {
                featureRowNodes[i].frame = CGRect(x: 0, y: fy, width: contentWidth, height: featureRowH)
                featureDotNodes[i].frame = CGRect(x: 16, y: (featureRowH - 8) / 2, width: 8, height: 8)
                featureLabelNodes[i].frame = CGRect(x: 32, y: 0, width: contentWidth - 48, height: featureRowH)
                fy += featureRowH
                
                if i < featureSepNodes.count {
                    featureSepNodes[i].frame = CGRect(x: 32, y: fy, width: contentWidth - 32, height: sepH)
                    fy += sepH
                }
            }
            
            y += totalH + 16
        }
        
        self.scrollNode?.view.contentSize = CGSize(width: width, height: y + bottomInset + 20)
    }
    
    @objc private func actionButtonTapped() {
        guard !self.isConnecting else { return }
        
        let settings = self.currentProxySettings ?? ProxySettings.defaultSettings
        
        if settings.enabled && settings.activeServer != nil {
            LitegramProxyController.shared.disconnect()
        } else {
            self.isConnecting = true
            self.actionButtonNode?.setTitle("Connecting...", with: UIFont.systemFont(ofSize: 17, weight: .semibold), with: .white, for: .normal)
            self.actionButtonNode?.alpha = 0.7
            LitegramProxyController.shared.reconnect()
        }
    }
    
    private func updateUI() {
        guard self.isNodeLoaded else { return }
        
        let theme = self.presentationData.theme
        let settings = self.currentProxySettings ?? ProxySettings.defaultSettings
        let isProxyEnabled = settings.enabled && settings.activeServer != nil
        
        var statusString: String
        var dotColor: UIColor
        var serverString: String
        var buttonTitle: String
        
        if isProxyEnabled {
            switch self.currentConnectionStatus {
            case .online:
                self.isConnecting = false
                self.actionButtonNode?.alpha = 1.0
                statusString = "Connected"
                dotColor = UIColor(rgb: 0x34C759)
                buttonTitle = "Disconnect"
            case .connecting:
                statusString = "Connecting..."
                dotColor = UIColor.orange
                buttonTitle = "Connecting..."
            case .updating:
                statusString = "Updating..."
                dotColor = UIColor.orange
                buttonTitle = "Disconnect"
            case .waitingForNetwork:
                statusString = "Waiting for network..."
                dotColor = UIColor.orange
                buttonTitle = "Disconnect"
            }
            
            if let server = settings.activeServer {
                serverString = "\(server.host):\(server.port)"
            } else {
                serverString = "—"
            }
        } else {
            self.isConnecting = false
            self.actionButtonNode?.alpha = 1.0
            statusString = "Disconnected"
            dotColor = UIColor.white.withAlphaComponent(0.5)
            serverString = "Not connected"
            buttonTitle = "Connect"
        }
        
        self.statusTextNode?.attributedText = NSAttributedString(string: statusString, attributes: [
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: UIColor.white
        ])
        self.statusDotNode?.backgroundColor = dotColor
        self.serverValueNode?.attributedText = NSAttributedString(string: serverString, attributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: theme.list.itemSecondaryTextColor])
        
        self.planValueNode?.attributedText = NSAttributedString(string: "Free", attributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: theme.list.itemSecondaryTextColor])
        
        self.actionButtonNode?.setTitle(buttonTitle, with: UIFont.systemFont(ofSize: 17, weight: .semibold), with: .white, for: .normal)
        
        if isProxyEnabled && buttonTitle != "Connect" {
            self.actionButtonGradient?.colors = [
                UIColor(rgb: 0xFF3B30).cgColor,
                UIColor(rgb: 0xFF6B6B).cgColor
            ]
        } else {
            self.actionButtonGradient?.colors = [
                UIColor(rgb: 0x6a94ff).cgColor,
                UIColor(rgb: 0x9472fd).cgColor,
                UIColor(rgb: 0xe26bd3).cgColor
            ]
        }
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
