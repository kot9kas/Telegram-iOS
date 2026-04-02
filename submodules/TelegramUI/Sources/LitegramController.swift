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

public final class LitegramController: ViewController {
    private let context: AccountContext
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    private var proxySettingsDisposable: Disposable?
    private var connectionStatusDisposable: Disposable?
    
    private var currentProxySettings: ProxySettings?
    private var currentConnectionStatus: ConnectionStatus = .waitingForNetwork
    
    private var scrollNode: ASScrollNode?
    
    private var statusDotNode: ASDisplayNode?
    private var statusTextNode: ASTextNode?
    private var serverRowNode: ASDisplayNode?
    private var serverTitleNode: ASTextNode?
    private var serverValueNode: ASTextNode?
    private var planRowNode: ASDisplayNode?
    private var planTitleNode: ASTextNode?
    private var planValueNode: ASTextNode?
    private var connectButtonNode: ASButtonNode?
    private var upsellNode: ASTextNode?
    
    private var isConnecting = false
    
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
            let scrollFrame = CGRect(x: 0, y: navBarHeight, width: layout.size.width, height: layout.size.height - navBarHeight)
            transition.updateFrame(node: scrollNode, frame: scrollFrame)
        }
        
        layoutNodes(width: layout.size.width, bottomInset: bottomInset)
    }
    
    private func setupNodes() {
        let theme = self.presentationData.theme
        
        let dot = ASDisplayNode()
        dot.cornerRadius = 6
        scrollNode?.addSubnode(dot)
        self.statusDotNode = dot
        
        let statusText = ASTextNode()
        scrollNode?.addSubnode(statusText)
        self.statusTextNode = statusText
        
        let serverRow = ASDisplayNode()
        serverRow.backgroundColor = theme.list.itemBlocksBackgroundColor
        serverRow.cornerRadius = 10
        scrollNode?.addSubnode(serverRow)
        self.serverRowNode = serverRow
        
        let serverTitle = ASTextNode()
        serverTitle.attributedText = NSAttributedString(string: "Server", attributes: [
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: theme.list.itemPrimaryTextColor
        ])
        serverRow.addSubnode(serverTitle)
        self.serverTitleNode = serverTitle
        
        let serverValue = ASTextNode()
        serverRow.addSubnode(serverValue)
        self.serverValueNode = serverValue
        
        let planRow = ASDisplayNode()
        planRow.backgroundColor = theme.list.itemBlocksBackgroundColor
        planRow.cornerRadius = 10
        scrollNode?.addSubnode(planRow)
        self.planRowNode = planRow
        
        let planTitle = ASTextNode()
        planTitle.attributedText = NSAttributedString(string: "Plan", attributes: [
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: theme.list.itemPrimaryTextColor
        ])
        planRow.addSubnode(planTitle)
        self.planTitleNode = planTitle
        
        let planValue = ASTextNode()
        planRow.addSubnode(planValue)
        self.planValueNode = planValue
        
        let button = ASButtonNode()
        button.cornerRadius = 10
        button.clipsToBounds = true
        button.addTarget(self, action: #selector(actionButtonTapped), forControlEvents: .touchUpInside)
        scrollNode?.addSubnode(button)
        self.connectButtonNode = button
        
        let upsell = ASTextNode()
        upsell.maximumNumberOfLines = 0
        scrollNode?.addSubnode(upsell)
        self.upsellNode = upsell
        
        updateUI()
    }
    
    private func updateColors() {
        let theme = self.presentationData.theme
        self.displayNode.backgroundColor = theme.list.blocksBackgroundColor
        self.serverRowNode?.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.planRowNode?.backgroundColor = theme.list.itemBlocksBackgroundColor
    }
    
    private func layoutNodes(width: CGFloat, bottomInset: CGFloat) {
        let inset: CGFloat = 22
        let contentWidth = width - inset * 2
        var y: CGFloat = 20
        
        let dotSize: CGFloat = 12
        self.statusDotNode?.frame = CGRect(x: inset, y: y + 4, width: dotSize, height: dotSize)
        self.statusTextNode?.frame = CGRect(x: inset + dotSize + 10, y: y, width: contentWidth - dotSize - 10, height: 22)
        y += 30 + 16
        
        let rowH: CGFloat = 44
        if let serverRow = self.serverRowNode {
            serverRow.frame = CGRect(x: inset, y: y, width: contentWidth, height: rowH)
            self.serverTitleNode?.frame = CGRect(x: 16, y: 0, width: 80, height: rowH)
            self.serverValueNode?.frame = CGRect(x: 96, y: 0, width: contentWidth - 112, height: rowH)
            y += rowH
        }
        
        let sepLine = CALayer()
        sepLine.backgroundColor = self.presentationData.theme.list.itemBlocksSeparatorColor.cgColor
        sepLine.frame = CGRect(x: inset + 16, y: y, width: contentWidth - 16, height: 0.5)
        self.scrollNode?.layer.addSublayer(sepLine)
        
        if let planRow = self.planRowNode {
            planRow.frame = CGRect(x: inset, y: y, width: contentWidth, height: rowH)
            self.planTitleNode?.frame = CGRect(x: 16, y: 0, width: 80, height: rowH)
            self.planValueNode?.frame = CGRect(x: 96, y: 0, width: contentWidth - 112, height: rowH)
            y += rowH + 20
        }
        
        if let button = self.connectButtonNode {
            button.frame = CGRect(x: inset, y: y, width: contentWidth, height: 50)
            y += 50 + 16
        }
        
        if let upsell = self.upsellNode {
            let upsellSize = upsell.measure(CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude))
            upsell.frame = CGRect(x: inset, y: y, width: contentWidth, height: upsellSize.height)
            y += upsellSize.height + 16
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
        var showConnect: Bool
        
        if isProxyEnabled {
            switch self.currentConnectionStatus {
            case .online:
                self.isConnecting = false
                statusString = "Connected"
                dotColor = UIColor(rgb: 0x34C759)
                showConnect = false
            case .connecting:
                statusString = "Connecting..."
                dotColor = UIColor(rgb: 0xFF9500)
                showConnect = false
            case .updating:
                statusString = "Updating..."
                dotColor = UIColor(rgb: 0xFF9500)
                showConnect = false
            case .waitingForNetwork:
                statusString = "Waiting for network..."
                dotColor = UIColor(rgb: 0xFF9500)
                showConnect = false
            }
            
            if let server = settings.activeServer {
                serverString = "\(server.host):\(server.port)"
            } else {
                serverString = "—"
            }
        } else {
            self.isConnecting = false
            statusString = "Disconnected"
            dotColor = UIColor(rgb: 0xFF3B30)
            serverString = "Not connected"
            showConnect = true
        }
        
        self.statusDotNode?.backgroundColor = dotColor
        self.statusTextNode?.attributedText = NSAttributedString(string: statusString, attributes: [
            .font: UIFont.systemFont(ofSize: 17, weight: .medium),
            .foregroundColor: theme.list.itemPrimaryTextColor
        ])
        
        self.serverValueNode?.attributedText = NSAttributedString(string: serverString, attributes: [
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: theme.list.itemSecondaryTextColor
        ])
        
        self.planValueNode?.attributedText = NSAttributedString(string: "Free", attributes: [
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: theme.list.itemSecondaryTextColor
        ])
        
        let accentColor = theme.list.itemAccentColor
        
        if showConnect {
            self.connectButtonNode?.setTitle("Connect", with: UIFont.systemFont(ofSize: 17, weight: .semibold), with: .white, for: .normal)
            self.connectButtonNode?.backgroundColor = accentColor
        } else if self.isConnecting {
            self.connectButtonNode?.setTitle("Connecting...", with: UIFont.systemFont(ofSize: 17, weight: .semibold), with: .white, for: .normal)
            self.connectButtonNode?.backgroundColor = accentColor.withAlphaComponent(0.6)
        } else {
            self.connectButtonNode?.setTitle("Disconnect", with: UIFont.systemFont(ofSize: 17, weight: .semibold), with: .white, for: .normal)
            self.connectButtonNode?.backgroundColor = UIColor(rgb: 0xFF3B30)
        }
        
        self.upsellNode?.attributedText = NSAttributedString(
            string: "Your region may require a subscription for stable access. Consider purchasing a subscription for uninterrupted connectivity.",
            attributes: [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: theme.list.itemSecondaryTextColor
            ]
        )
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
