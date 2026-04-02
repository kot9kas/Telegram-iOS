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
    private var headerNode: ASDisplayNode?
    private var statusDotNode: ASDisplayNode?
    private var statusTextNode: ASTextNode?
    private var subtitleTextNode: ASTextNode?
    private var serverTitleNode: ASTextNode?
    private var serverRowNode: ASDisplayNode?
    private var serverValueNode: ASTextNode?
    private var planTitleNode: ASTextNode?
    private var planRowNode: ASDisplayNode?
    private var planValueNode: ASTextNode?
    private var actionButtonNode: ASButtonNode?
    private var featuresContainerNode: ASDisplayNode?
    private var featureRowNodes: [ASDisplayNode] = []
    private var featureLabelNodes: [ASTextNode] = []
    private var featureSepNodes: [ASDisplayNode] = []
    
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
        
        let header = ASDisplayNode()
        header.clipsToBounds = true
        header.cornerRadius = 12
        scrollNode?.addSubnode(header)
        self.headerNode = header
        
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor(red: 0xAE/255.0, green: 0x8B/255.0, blue: 0xA1/255.0, alpha: 1.0).cgColor,
            UIColor(red: 0xF2/255.0, green: 0xEC/255.0, blue: 0xB6/255.0, alpha: 1.0).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        header.layer.insertSublayer(gradientLayer, at: 0)
        
        let dot = ASDisplayNode()
        dot.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        dot.cornerRadius = 5
        header.addSubnode(dot)
        self.statusDotNode = dot
        
        let statusText = ASTextNode()
        statusText.attributedText = NSAttributedString(string: "Disconnected", attributes: [.font: UIFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: UIColor.white])
        header.addSubnode(statusText)
        self.statusTextNode = statusText
        
        let subtitle = ASTextNode()
        subtitle.attributedText = NSAttributedString(string: "Secure proxy for unrestricted access", attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .regular), .foregroundColor: UIColor.white.withAlphaComponent(0.85)])
        subtitle.maximumNumberOfLines = 2
        header.addSubnode(subtitle)
        self.subtitleTextNode = subtitle
        
        let serverRow = ASDisplayNode()
        serverRow.backgroundColor = theme.list.itemBlocksBackgroundColor
        serverRow.cornerRadius = 10
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
        planRow.cornerRadius = 10
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
        
        let button = ASButtonNode()
        button.setTitle("Connect", with: UIFont.systemFont(ofSize: 17, weight: .semibold), with: .white, for: .normal)
        button.backgroundColor = theme.list.itemAccentColor
        button.cornerRadius = 10
        button.addTarget(self, action: #selector(actionButtonTapped), forControlEvents: .touchUpInside)
        scrollNode?.addSubnode(button)
        self.actionButtonNode = button
        
        let featuresContainer = ASDisplayNode()
        featuresContainer.backgroundColor = theme.list.itemBlocksBackgroundColor
        featuresContainer.cornerRadius = 10
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
        self.actionButtonNode?.backgroundColor = theme.list.itemAccentColor
        self.featuresContainerNode?.backgroundColor = theme.list.itemBlocksBackgroundColor
    }
    
    private func layoutNodes(width: CGFloat, bottomInset: CGFloat) {
        let padding: CGFloat = 16
        let contentWidth = width - padding * 2
        var y: CGFloat = 16
        
        if let header = self.headerNode {
            let headerFrame = CGRect(x: padding, y: y, width: contentWidth, height: 120)
            header.frame = headerFrame
            if let gradient = header.layer.sublayers?.first as? CAGradientLayer {
                gradient.frame = CGRect(origin: .zero, size: headerFrame.size)
            }
            self.statusDotNode?.frame = CGRect(x: 20, y: 24, width: 10, height: 10)
            self.statusTextNode?.frame = CGRect(x: 36, y: 17, width: contentWidth - 56, height: 28)
            self.subtitleTextNode?.frame = CGRect(x: 20, y: 52, width: contentWidth - 40, height: 50)
            y += 120 + 12
        }
        
        let rowH: CGFloat = 44
        if let serverRow = self.serverRowNode {
            serverRow.frame = CGRect(x: padding, y: y, width: contentWidth, height: rowH)
            self.serverTitleNode?.frame = CGRect(x: 16, y: 0, width: contentWidth * 0.4, height: rowH)
            self.serverValueNode?.frame = CGRect(x: contentWidth * 0.4, y: 0, width: contentWidth * 0.6 - 16, height: rowH)
            y += rowH + 8
        }
        
        if let planRow = self.planRowNode {
            planRow.frame = CGRect(x: padding, y: y, width: contentWidth, height: rowH)
            self.planTitleNode?.frame = CGRect(x: 16, y: 0, width: contentWidth * 0.4, height: rowH)
            self.planValueNode?.frame = CGRect(x: contentWidth * 0.4, y: 0, width: contentWidth * 0.6 - 16, height: rowH)
            y += rowH + 16
        }
        
        if let button = self.actionButtonNode {
            button.frame = CGRect(x: padding, y: y, width: contentWidth, height: 50)
            y += 50 + 16
        }
        
        if let _ = self.featuresContainerNode {
            let featureRowH: CGFloat = 44
            let sepH: CGFloat = 0.5
            let count = featureRowNodes.count
            let totalH = CGFloat(count) * featureRowH + CGFloat(featureSepNodes.count) * sepH
            self.featuresContainerNode?.frame = CGRect(x: padding, y: y, width: contentWidth, height: totalH)
            
            var fy: CGFloat = 0
            for i in 0..<count {
                featureRowNodes[i].frame = CGRect(x: 0, y: fy, width: contentWidth, height: featureRowH)
                featureLabelNodes[i].frame = CGRect(x: 16, y: 0, width: contentWidth - 32, height: featureRowH)
                fy += featureRowH
                
                if i < featureSepNodes.count {
                    featureSepNodes[i].frame = CGRect(x: 16, y: fy, width: contentWidth - 16, height: sepH)
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
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.isConnecting = false
                self?.actionButtonNode?.alpha = 1.0
                self?.updateUI()
            }
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
                statusString = "Connected"
                dotColor = UIColor(red: 0x34/255.0, green: 0xC7/255.0, blue: 0x59/255.0, alpha: 1.0)
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
            statusString = "Disconnected"
            dotColor = UIColor.white.withAlphaComponent(0.5)
            serverString = "Not connected"
            buttonTitle = "Connect"
        }
        
        self.statusTextNode?.attributedText = NSAttributedString(string: statusString, attributes: [.font: UIFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: UIColor.white])
        self.statusDotNode?.backgroundColor = dotColor
        self.serverValueNode?.attributedText = NSAttributedString(string: serverString, attributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: theme.list.itemSecondaryTextColor])
        
        let planStr = LitegramDeviceToken.hasAccessToken ? "Premium" : "Free"
        self.planValueNode?.attributedText = NSAttributedString(string: planStr, attributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: theme.list.itemSecondaryTextColor])
        
        if !self.isConnecting {
            self.actionButtonNode?.setTitle(buttonTitle, with: UIFont.systemFont(ofSize: 17, weight: .semibold), with: .white, for: .normal)
            
            if isProxyEnabled {
                self.actionButtonNode?.backgroundColor = UIColor(red: 0xFF/255.0, green: 0x3B/255.0, blue: 0x30/255.0, alpha: 1.0)
            } else {
                self.actionButtonNode?.backgroundColor = theme.list.itemAccentColor
            }
        }
    }
}
