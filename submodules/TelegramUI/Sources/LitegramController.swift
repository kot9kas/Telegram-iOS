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
    private var connectedAnimNode: AnimatedStickerNode?
    private var disconnectedAnimNode: AnimatedStickerNode?
    private var activeAnimNode: AnimatedStickerNode?
    private var headerTitleNode: ASTextNode?
    private var headerSubtitleNode: ASTextNode?
    
    private var serverRowNode: ASDisplayNode?
    private var serverTitleNode: ASTextNode?
    private var serverValueNode: ASTextNode?
    
    private var connectButtonNode: ASButtonNode?
    
    private var perksHeaderNode: ASTextNode?
    private var perksContainerNode: ASDisplayNode?
    private var perkNodes: [(bg: ASDisplayNode, icon: ASImageNode, title: ASTextNode, subtitle: ASTextNode, arrow: ASImageNode)] = []
    private var perkSepNodes: [ASDisplayNode] = []
    
    private var isConnecting = false
    private var lastAnimName: String?
    private var animSetupPending = false
    
    private static let gradientColors: [UIColor] = [
        UIColor(rgb: 0xef6922),
        UIColor(rgb: 0xe54937),
        UIColor(rgb: 0xdb374b),
        UIColor(rgb: 0xab4ac4),
        UIColor(rgb: 0x676bff),
        UIColor(rgb: 0x4492ff),
        UIColor(rgb: 0x3eb26d)
    ]
    
    private static let perks: [(icon: String, title: String, subtitle: String)] = [
        ("Premium/Perk/Speed", "Fast and stable", "High-speed proxy with zero throttling"),
        ("Premium/Perk/NoForward", "Enhanced privacy", "Your traffic is encrypted end-to-end"),
        ("Premium/Perk/NoAds", "Access blocked content", "Bypass regional restrictions seamlessly"),
        ("Premium/Perk/Limits", "No speed limits", "Unlimited bandwidth for all your needs"),
        ("Premium/Perk/Chat", "Auto-reconnect", "Stays connected even on unstable networks"),
        ("Premium/Perk/Status", "Multiple servers", "Choose from servers across the globe"),
        ("Premium/Perk/Translation", "Easy to use", "One-tap connect, no configuration needed")
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
                self.currentProxySettings = sharedData.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? ProxySettings.defaultSettings
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
            self.displayNode.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
            self.updateUI()
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
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.connectedAnimNode?.visibility = true
            self.disconnectedAnimNode?.visibility = true
            self.activeAnimNode?.playOnce()
        }
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let navBarHeight = self.navigationLayout(layout: layout).navigationFrame.maxY
        let bottomInset = layout.intrinsicInsets.bottom
        if let scrollNode = self.scrollNode {
            transition.updateFrame(node: scrollNode, frame: CGRect(x: 0, y: navBarHeight, width: layout.size.width, height: layout.size.height - navBarHeight))
        }
        layoutNodes(width: layout.size.width, bottomInset: bottomInset)
        
        if self.animSetupPending {
            self.animSetupPending = false
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.connectedAnimNode?.visibility = true
                self.disconnectedAnimNode?.visibility = true
                self.activeAnimNode?.playOnce()
            }
        }
    }
    
    // MARK: - Setup
    
    private func setupNodes() {
        let theme = self.presentationData.theme
        
        let header = ASDisplayNode()
        header.clipsToBounds = true
        header.cornerRadius = 16
        scrollNode?.addSubnode(header)
        self.headerNode = header
        
        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(rgb: 0xAE8BA1).cgColor,
            UIColor(rgb: 0xF2ECB6).cgColor
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        header.layer.insertSublayer(gradient, at: 0)
        
        header.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(headerTapped)))
        
        let pixelSize: Int = Int(80.0 * UIScreen.main.scale)
        
        let connAnim = DefaultAnimatedStickerNodeImpl()
        connAnim.automaticallyLoadFirstFrame = true
        connAnim.setup(source: AnimatedStickerNodeLocalFileSource(name: "change_number"), width: pixelSize, height: pixelSize, playbackMode: .once, mode: .direct(cachePathPrefix: nil))
        connAnim.isHidden = true
        header.addSubnode(connAnim)
        self.connectedAnimNode = connAnim
        
        let discAnim = DefaultAnimatedStickerNodeImpl()
        discAnim.automaticallyLoadFirstFrame = true
        discAnim.setup(source: AnimatedStickerNodeLocalFileSource(name: "media_forbidden"), width: pixelSize, height: pixelSize, playbackMode: .once, mode: .direct(cachePathPrefix: nil))
        discAnim.isHidden = true
        header.addSubnode(discAnim)
        self.disconnectedAnimNode = discAnim
        
        let title = ASTextNode()
        title.textAlignment = .center
        header.addSubnode(title)
        self.headerTitleNode = title
        
        let subtitle = ASTextNode()
        subtitle.textAlignment = .center
        subtitle.maximumNumberOfLines = 2
        header.addSubnode(subtitle)
        self.headerSubtitleNode = subtitle
        
        let serverRow = ASDisplayNode()
        serverRow.backgroundColor = theme.list.itemBlocksBackgroundColor
        serverRow.cornerRadius = 12
        scrollNode?.addSubnode(serverRow)
        self.serverRowNode = serverRow
        
        let serverTitle = ASTextNode()
        serverTitle.attributedText = NSAttributedString(string: "Server", attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: theme.list.itemPrimaryTextColor])
        serverRow.addSubnode(serverTitle)
        self.serverTitleNode = serverTitle
        
        let serverValue = ASTextNode()
        serverValue.textAlignment = .right
        serverRow.addSubnode(serverValue)
        self.serverValueNode = serverValue
        
        let button = ASButtonNode()
        button.cornerRadius = 12
        button.clipsToBounds = true
        button.addTarget(self, action: #selector(actionButtonTapped), forControlEvents: .touchUpInside)
        scrollNode?.addSubnode(button)
        self.connectButtonNode = button
        
        let perksHeader = ASTextNode()
        perksHeader.attributedText = NSAttributedString(string: "WHAT'S INCLUDED", attributes: [
            .font: UIFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: theme.list.itemSecondaryTextColor,
            .kern: 0.5
        ])
        scrollNode?.addSubnode(perksHeader)
        self.perksHeaderNode = perksHeader
        
        let perksContainer = ASDisplayNode()
        perksContainer.backgroundColor = theme.list.itemBlocksBackgroundColor
        perksContainer.cornerRadius = 12
        perksContainer.clipsToBounds = true
        scrollNode?.addSubnode(perksContainer)
        self.perksContainerNode = perksContainer
        
        for (i, perk) in Self.perks.enumerated() {
            let color = Self.gradientColors[i % Self.gradientColors.count]
            
            let bg = ASDisplayNode()
            bg.backgroundColor = color
            bg.cornerRadius = 7
            perksContainer.addSubnode(bg)
            
            let iconNode = ASImageNode()
            iconNode.contentMode = .scaleAspectFit
            iconNode.displaysAsynchronously = false
            if let img = UIImage(bundleImageName: perk.icon)?.withRenderingMode(.alwaysTemplate) {
                iconNode.image = img
            }
            iconNode.tintColor = .white
            bg.addSubnode(iconNode)
            
            let titleNode = ASTextNode()
            titleNode.attributedText = NSAttributedString(string: perk.title, attributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .regular),
                .foregroundColor: theme.list.itemPrimaryTextColor
            ])
            perksContainer.addSubnode(titleNode)
            
            let subtitleNode = ASTextNode()
            subtitleNode.attributedText = NSAttributedString(string: perk.subtitle, attributes: [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: theme.list.itemSecondaryTextColor
            ])
            perksContainer.addSubnode(subtitleNode)
            
            let arrow = ASImageNode()
            arrow.displaysAsynchronously = false
            arrow.image = UIImage(bundleImageName: "Item List/DisclosureArrow")
            perksContainer.addSubnode(arrow)
            
            self.perkNodes.append((bg: bg, icon: iconNode, title: titleNode, subtitle: subtitleNode, arrow: arrow))
            
            if i < Self.perks.count - 1 {
                let sep = ASDisplayNode()
                sep.backgroundColor = theme.list.itemBlocksSeparatorColor
                perksContainer.addSubnode(sep)
                self.perkSepNodes.append(sep)
            }
        }
        
        updateUI()
    }
    
    // MARK: - Layout
    
    private func layoutNodes(width: CGFloat, bottomInset: CGFloat) {
        let pad: CGFloat = 16
        let cw = width - pad * 2
        var y: CGFloat = 12
        
        let animSize: CGFloat = 80
        let titleH: CGFloat = 34
        let subtitleH: CGFloat = 20
        let headerH: CGFloat = animSize + titleH + subtitleH + 52
        
        if let header = self.headerNode {
            header.frame = CGRect(x: pad, y: y, width: cw, height: headerH)
            if let g = header.layer.sublayers?.first as? CAGradientLayer {
                g.frame = CGRect(origin: .zero, size: CGSize(width: cw, height: headerH))
            }
            
            let contentH = animSize + 8 + titleH + 2 + subtitleH
            let topPad = (headerH - contentH) / 2
            let animFrame = CGRect(x: (cw - animSize) / 2, y: topPad, width: animSize, height: animSize)
            let animLayoutSize = CGSize(width: animSize, height: animSize)
            self.connectedAnimNode?.frame = animFrame
            self.connectedAnimNode?.updateLayout(size: animLayoutSize)
            self.disconnectedAnimNode?.frame = animFrame
            self.disconnectedAnimNode?.updateLayout(size: animLayoutSize)
            
            let ty = topPad + animSize + 8
            self.headerTitleNode?.frame = CGRect(x: 0, y: ty, width: cw, height: titleH)
            self.headerSubtitleNode?.frame = CGRect(x: 20, y: ty + titleH + 2, width: cw - 40, height: subtitleH)
            
            y += headerH + 12
        }
        
        let rowH: CGFloat = 48
        let textH: CGFloat = 22
        let textY: CGFloat = (rowH - textH) / 2
        if let sr = self.serverRowNode {
            sr.frame = CGRect(x: pad, y: y, width: cw, height: rowH)
            self.serverTitleNode?.frame = CGRect(x: 16, y: textY, width: 80, height: textH)
            self.serverValueNode?.frame = CGRect(x: 96, y: textY, width: cw - 112, height: textH)
            y += rowH + 16
        }
        
        if let btn = self.connectButtonNode {
            btn.frame = CGRect(x: pad, y: y, width: cw, height: 50)
            y += 50 + 24
        }
        
        self.perksHeaderNode?.frame = CGRect(x: pad + 16, y: y, width: cw, height: 18)
        y += 26
        
        if let _ = self.perksContainerNode {
            let perkH: CGFloat = 60
            let sepH: CGFloat = 0.5
            let count = perkNodes.count
            let totalH = CGFloat(count) * perkH + CGFloat(perkSepNodes.count) * sepH
            self.perksContainerNode?.frame = CGRect(x: pad, y: y, width: cw, height: totalH)
            
            let iconSize: CGFloat = 30
            let iconInset: CGFloat = 12
            let textX: CGFloat = iconInset + iconSize + 12
            let arrowSize: CGFloat = 14
            
            var fy: CGFloat = 0
            for i in 0..<count {
                let node = perkNodes[i]
                
                node.bg.frame = CGRect(x: iconInset, y: fy + (perkH - iconSize) / 2, width: iconSize, height: iconSize)
                node.icon.frame = CGRect(x: 4, y: 4, width: iconSize - 8, height: iconSize - 8)
                
                node.title.frame = CGRect(x: textX, y: fy + 9, width: cw - textX - 30, height: 20)
                node.subtitle.frame = CGRect(x: textX, y: fy + 9 + 20 + 2, width: cw - textX - 30, height: 16)
                
                node.arrow.frame = CGRect(x: cw - arrowSize - 16, y: fy + (perkH - arrowSize) / 2, width: arrowSize, height: arrowSize)
                
                fy += perkH
                if i < perkSepNodes.count {
                    perkSepNodes[i].frame = CGRect(x: textX, y: fy, width: cw - textX, height: sepH)
                    fy += sepH
                }
            }
            y += totalH + 16
        }
        
        self.scrollNode?.view.contentSize = CGSize(width: width, height: y + bottomInset + 20)
    }
    
    // MARK: - Actions
    
    @objc private func headerTapped() {
        self.activeAnimNode?.playOnce()
    }
    
    @objc private func actionButtonTapped() {
        guard !self.isConnecting else { return }
        let settings = self.currentProxySettings ?? ProxySettings.defaultSettings
        if settings.enabled && settings.activeServer != nil {
            LitegramProxyController.shared.disconnect()
        } else {
            self.isConnecting = true
            LitegramProxyController.shared.reconnect()
            updateUI()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
                guard let self = self, self.isConnecting else { return }
                self.isConnecting = false
                self.updateUI()
                let alert = UIAlertController(title: "Connection Failed", message: "Could not connect to proxy server. Please check your internet connection and try again.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
            return
        }
        updateUI()
    }
    
    // MARK: - Update
    
    private func updateUI() {
        guard self.isNodeLoaded else { return }
        let theme = self.presentationData.theme
        let settings = self.currentProxySettings ?? ProxySettings.defaultSettings
        let isProxy = settings.enabled && settings.activeServer != nil
        
        var titleStr: String
        var subtitleStr: String
        var animName: String
        var serverStr: String
        var btnTitle: String
        var btnColor: UIColor
        
        if isProxy {
            switch self.currentConnectionStatus {
            case .online:
                self.isConnecting = false
                titleStr = "Connected"
                subtitleStr = "Connected securely via proxy"
                animName = "change_number"
                btnTitle = "Disconnect"
                btnColor = UIColor(rgb: 0xFF3B30)
            case .connecting:
                titleStr = "Connecting..."
                subtitleStr = "Establishing secure connection"
                animName = "media_forbidden"
                btnTitle = "Connecting..."
                btnColor = theme.list.itemAccentColor.withAlphaComponent(0.6)
            case .updating:
                titleStr = "Updating..."
                subtitleStr = "Refreshing connection"
                animName = "change_number"
                btnTitle = "Disconnect"
                btnColor = UIColor(rgb: 0xFF3B30)
            case .waitingForNetwork:
                titleStr = "Waiting for network..."
                subtitleStr = "No internet connection"
                animName = "media_forbidden"
                btnTitle = "Disconnect"
                btnColor = UIColor(rgb: 0xFF3B30)
            }
            
            if let server = LitegramProxyController.shared.lastConnectedServer, !server.name.isEmpty {
                serverStr = "\(server.name) | \(server.country.uppercased())"
            } else if let server = settings.activeServer {
                serverStr = "\(server.host):\(server.port)"
            } else {
                serverStr = "—"
            }
        } else {
            self.isConnecting = false
            titleStr = "Disconnected"
            subtitleStr = "Tap Connect to enable proxy"
            animName = "media_forbidden"
            serverStr = "Not connected"
            btnTitle = "Connect"
            btnColor = theme.list.itemAccentColor
        }
        
        self.headerTitleNode?.attributedText = NSAttributedString(string: titleStr, attributes: [
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: UIColor.white
        ])
        
        self.headerSubtitleNode?.attributedText = NSAttributedString(string: subtitleStr, attributes: [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: UIColor.white.withAlphaComponent(0.85)
        ])
        
        let isConnectedAnim = (animName == "change_number")
        let targetNode = isConnectedAnim ? self.connectedAnimNode : self.disconnectedAnimNode
        let otherNode = isConnectedAnim ? self.disconnectedAnimNode : self.connectedAnimNode
        
        if self.activeAnimNode !== targetNode || self.lastAnimName != animName {
            self.lastAnimName = animName
            otherNode?.isHidden = true
            targetNode?.isHidden = false
            self.activeAnimNode = targetNode
            self.animSetupPending = true
            targetNode?.visibility = true
            targetNode?.playOnce()
        }
        
        self.serverValueNode?.attributedText = NSAttributedString(string: serverStr, attributes: [
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: theme.list.itemSecondaryTextColor
        ])
        
        self.connectButtonNode?.setTitle(btnTitle, with: UIFont.systemFont(ofSize: 17, weight: .semibold), with: .white, for: .normal)
        self.connectButtonNode?.backgroundColor = btnColor
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
