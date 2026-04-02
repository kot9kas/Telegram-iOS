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
    private var headerAnimNode: AnimatedStickerNode?
    private var headerTitleNode: ASTextNode?
    private var headerSubtitleNode: ASTextNode?
    
    private var serverRowNode: ASDisplayNode?
    private var serverTitleNode: ASTextNode?
    private var serverValueNode: ASTextNode?
    
    private var connectButtonNode: ASButtonNode?
    
    private var perksHeaderNode: ASTextNode?
    private var perksContainerNode: ASDisplayNode?
    private var perkIconNodes: [ASDisplayNode] = []
    private var perkLabelNodes: [ASTextNode] = []
    private var perkSepNodes: [ASDisplayNode] = []
    
    private var isConnecting = false
    private var lastAnimName: String?
    
    private static let perks: [(icon: String, color: UInt32, text: String)] = [
        ("lock.shield", 0xef6922, "Access blocked content"),
        ("eye.slash", 0xe54937, "Enhanced privacy protection"),
        ("bolt", 0xab4ac4, "Fast and stable connection"),
        ("speedometer", 0x676bff, "No speed limitations"),
        ("arrow.triangle.2.circlepath", 0x3eb26d, "Auto-reconnect support")
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
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let navBarHeight = self.navigationLayout(layout: layout).navigationFrame.maxY
        let bottomInset = layout.intrinsicInsets.bottom
        if let scrollNode = self.scrollNode {
            transition.updateFrame(node: scrollNode, frame: CGRect(x: 0, y: navBarHeight, width: layout.size.width, height: layout.size.height - navBarHeight))
        }
        layoutNodes(width: layout.size.width, bottomInset: bottomInset)
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
        
        let animNode = DefaultAnimatedStickerNodeImpl()
        header.addSubnode(animNode)
        self.headerAnimNode = animNode
        
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
        serverRow.addSubnode(serverValue)
        self.serverValueNode = serverValue
        
        let button = ASButtonNode()
        button.cornerRadius = 12
        button.clipsToBounds = true
        button.addTarget(self, action: #selector(actionButtonTapped), forControlEvents: .touchUpInside)
        scrollNode?.addSubnode(button)
        self.connectButtonNode = button
        
        let perksHeader = ASTextNode()
        perksHeader.attributedText = NSAttributedString(string: "FEATURES", attributes: [
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
            let iconBg = ASDisplayNode()
            iconBg.backgroundColor = UIColor(rgb: perk.color)
            iconBg.cornerRadius = 7
            perksContainer.addSubnode(iconBg)
            self.perkIconNodes.append(iconBg)
            
            let label = ASTextNode()
            label.attributedText = NSAttributedString(string: perk.text, attributes: [
                .font: UIFont.systemFont(ofSize: 16),
                .foregroundColor: theme.list.itemPrimaryTextColor
            ])
            perksContainer.addSubnode(label)
            self.perkLabelNodes.append(label)
            
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
        
        let headerH: CGFloat = 200
        if let header = self.headerNode {
            header.frame = CGRect(x: pad, y: y, width: cw, height: headerH)
            if let g = header.layer.sublayers?.first as? CAGradientLayer {
                g.frame = CGRect(origin: .zero, size: CGSize(width: cw, height: headerH))
            }
            
            let animSize: CGFloat = 80
            self.headerAnimNode?.frame = CGRect(x: (cw - animSize) / 2, y: 20, width: animSize, height: animSize)
            self.headerAnimNode?.updateLayout(size: CGSize(width: animSize, height: animSize))
            
            let ty: CGFloat = 20 + animSize + 10
            self.headerTitleNode?.frame = CGRect(x: 0, y: ty, width: cw, height: 34)
            self.headerSubtitleNode?.frame = CGRect(x: 20, y: ty + 34, width: cw - 40, height: 40)
            
            y += headerH + 12
        }
        
        let rowH: CGFloat = 48
        if let sr = self.serverRowNode {
            sr.frame = CGRect(x: pad, y: y, width: cw, height: rowH)
            self.serverTitleNode?.frame = CGRect(x: 16, y: 0, width: 80, height: rowH)
            self.serverValueNode?.frame = CGRect(x: 96, y: 0, width: cw - 112, height: rowH)
            y += rowH + 16
        }
        
        if let btn = self.connectButtonNode {
            btn.frame = CGRect(x: pad, y: y, width: cw, height: 50)
            y += 50 + 24
        }
        
        self.perksHeaderNode?.frame = CGRect(x: pad + 16, y: y, width: cw, height: 18)
        y += 26
        
        if let _ = self.perksContainerNode {
            let perkH: CGFloat = 52
            let sepH: CGFloat = 0.5
            let count = perkIconNodes.count
            let totalH = CGFloat(count) * perkH + CGFloat(perkSepNodes.count) * sepH
            self.perksContainerNode?.frame = CGRect(x: pad, y: y, width: cw, height: totalH)
            
            var fy: CGFloat = 0
            for i in 0..<count {
                let iconSize: CGFloat = 30
                perkIconNodes[i].frame = CGRect(x: 12, y: (perkH - iconSize) / 2 + fy, width: iconSize, height: iconSize)
                perkLabelNodes[i].frame = CGRect(x: 52, y: fy, width: cw - 68, height: perkH)
                fy += perkH
                if i < perkSepNodes.count {
                    perkSepNodes[i].frame = CGRect(x: 52, y: fy, width: cw - 52, height: sepH)
                    fy += sepH
                }
            }
            y += totalH + 16
        }
        
        self.scrollNode?.view.contentSize = CGSize(width: width, height: y + bottomInset + 20)
    }
    
    // MARK: - Actions
    
    @objc private func actionButtonTapped() {
        guard !self.isConnecting else { return }
        let settings = self.currentProxySettings ?? ProxySettings.defaultSettings
        if settings.enabled && settings.activeServer != nil {
            LitegramProxyController.shared.disconnect()
        } else {
            self.isConnecting = true
            LitegramProxyController.shared.reconnect()
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
        
        if animName != self.lastAnimName {
            self.lastAnimName = animName
            let animSize: Int = Int(80.0 * UIScreen.main.scale)
            self.headerAnimNode?.setup(source: AnimatedStickerNodeLocalFileSource(name: animName), width: animSize, height: animSize, playbackMode: .loop, mode: .direct(cachePathPrefix: nil))
            self.headerAnimNode?.visibility = true
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
