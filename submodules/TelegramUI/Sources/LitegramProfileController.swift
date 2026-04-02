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
import AvatarNode
import Litegram

public final class LitegramController: ViewController {
    private let context: AccountContext
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    private var peerDisposable: Disposable?
    
    private var scrollNode: ASScrollNode?
    
    private var profileSectionNode: ASDisplayNode?
    private var avatarNode: AvatarNode?
    private var nameNode: ASTextNode?
    private var idNode: ASTextNode?
    private var badgeNode: ASTextNode?
    private var badgeBgNode: ASDisplayNode?
    
    private var menuSectionNode: ASDisplayNode?
    private var protectionRow: ASDisplayNode?
    private var protectionIcon: ASImageNode?
    private var protectionTitle: ASTextNode?
    private var protectionSubtitle: ASTextNode?
    private var protectionArrow: ASImageNode?
    
    private var currentPeer: EnginePeer?
    
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
        
        self.peerDisposable = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
            |> deliverOnMainQueue).startStrict(next: { [weak self] peer in
                guard let self = self else { return }
                self.currentPeer = peer
                if self.isNodeLoaded {
                    self.updateProfile()
                }
            })
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.presentationDataDisposable?.dispose()
        self.peerDisposable?.dispose()
    }
    
    private func updateTheme() {
        self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: self.presentationData), transition: .immediate)
        if self.isNodeLoaded {
            self.displayNode.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
            self.updateProfile()
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
        
        let profileSection = ASDisplayNode()
        profileSection.backgroundColor = theme.list.itemBlocksBackgroundColor
        profileSection.cornerRadius = 12
        scrollNode?.addSubnode(profileSection)
        self.profileSectionNode = profileSection
        
        let avatar = AvatarNode(font: avatarPlaceholderFont(size: 26))
        profileSection.addSubnode(avatar)
        self.avatarNode = avatar
        
        let nameNode = ASTextNode()
        nameNode.textAlignment = .center
        nameNode.maximumNumberOfLines = 1
        profileSection.addSubnode(nameNode)
        self.nameNode = nameNode
        
        let idNode = ASTextNode()
        idNode.textAlignment = .center
        profileSection.addSubnode(idNode)
        self.idNode = idNode
        
        let badgeBg = ASDisplayNode()
        badgeBg.cornerRadius = 12
        profileSection.addSubnode(badgeBg)
        self.badgeBgNode = badgeBg
        
        let badge = ASTextNode()
        badge.textAlignment = .center
        badgeBg.addSubnode(badge)
        self.badgeNode = badge
        
        let menuSection = ASDisplayNode()
        menuSection.backgroundColor = theme.list.itemBlocksBackgroundColor
        menuSection.cornerRadius = 12
        scrollNode?.addSubnode(menuSection)
        self.menuSectionNode = menuSection
        
        let protectionRow = ASDisplayNode()
        menuSection.addSubnode(protectionRow)
        protectionRow.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(protectionTapped)))
        self.protectionRow = protectionRow
        
        let protIcon = ASImageNode()
        protIcon.displaysAsynchronously = false
        protIcon.image = UIImage(bundleImageName: "Settings/Menu/Proxy")
        protIcon.contentMode = .scaleAspectFit
        protectionRow.addSubnode(protIcon)
        self.protectionIcon = protIcon
        
        let protTitle = ASTextNode()
        protTitle.attributedText = NSAttributedString(string: "Protection", attributes: [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: theme.list.itemPrimaryTextColor
        ])
        protectionRow.addSubnode(protTitle)
        self.protectionTitle = protTitle
        
        let protSub = ASTextNode()
        protSub.attributedText = NSAttributedString(string: "Proxy settings and connection", attributes: [
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: theme.list.itemSecondaryTextColor
        ])
        protectionRow.addSubnode(protSub)
        self.protectionSubtitle = protSub
        
        let protArrow = ASImageNode()
        protArrow.displaysAsynchronously = false
        protArrow.image = UIImage(bundleImageName: "Item List/DisclosureArrow")
        protectionRow.addSubnode(protArrow)
        self.protectionArrow = protArrow
        
        updateProfile()
    }
    
    // MARK: - Layout
    
    private func layoutNodes(width: CGFloat, bottomInset: CGFloat) {
        let pad: CGFloat = 16
        let cw = width - pad * 2
        var y: CGFloat = 12
        
        let avatarSize: CGFloat = 80
        let profileH: CGFloat = avatarSize + 12 + 24 + 4 + 18 + 10 + 28 + 24
        
        if let section = self.profileSectionNode {
            section.frame = CGRect(x: pad, y: y, width: cw, height: profileH)
            
            let topPad: CGFloat = 24
            self.avatarNode?.frame = CGRect(x: (cw - avatarSize) / 2, y: topPad, width: avatarSize, height: avatarSize)
            
            let nameY = topPad + avatarSize + 12
            self.nameNode?.frame = CGRect(x: 16, y: nameY, width: cw - 32, height: 24)
            
            let idY = nameY + 24 + 4
            self.idNode?.frame = CGRect(x: 16, y: idY, width: cw - 32, height: 18)
            
            let badgeY = idY + 18 + 10
            let badgeW: CGFloat = 80
            let badgeH: CGFloat = 28
            self.badgeBgNode?.frame = CGRect(x: (cw - badgeW) / 2, y: badgeY, width: badgeW, height: badgeH)
            self.badgeNode?.frame = CGRect(x: 0, y: 0, width: badgeW, height: badgeH)
            
            y += profileH + 12
        }
        
        let menuRowH: CGFloat = 60
        if let menu = self.menuSectionNode {
            menu.frame = CGRect(x: pad, y: y, width: cw, height: menuRowH)
            self.protectionRow?.frame = CGRect(x: 0, y: 0, width: cw, height: menuRowH)
            
            let iconSize: CGFloat = 28
            self.protectionIcon?.frame = CGRect(x: 16, y: (menuRowH - iconSize) / 2, width: iconSize, height: iconSize)
            
            let textX: CGFloat = 54
            self.protectionTitle?.frame = CGRect(x: textX, y: 10, width: cw - textX - 30, height: 20)
            self.protectionSubtitle?.frame = CGRect(x: textX, y: 32, width: cw - textX - 30, height: 18)
            
            let arrowSize: CGFloat = 14
            self.protectionArrow?.frame = CGRect(x: cw - arrowSize - 16, y: (menuRowH - arrowSize) / 2, width: arrowSize, height: arrowSize)
            
            y += menuRowH + 16
        }
        
        self.scrollNode?.view.contentSize = CGSize(width: width, height: y + bottomInset + 20)
    }
    
    // MARK: - Actions
    
    @objc private func protectionTapped() {
        let connectionController = LitegramConnectionController(context: self.context)
        self.push(connectionController)
    }
    
    // MARK: - Update
    
    private func updateProfile() {
        let theme = self.presentationData.theme
        
        if let peer = self.currentPeer {
            self.avatarNode?.setPeer(
                context: self.context,
                theme: theme,
                peer: peer
            )
            
            let name: String
            switch peer {
            case let .user(user):
                var components: [String] = []
                if let firstName = user.firstName, !firstName.isEmpty { components.append(firstName) }
                if let lastName = user.lastName, !lastName.isEmpty { components.append(lastName) }
                name = components.joined(separator: " ")
            default:
                name = peer.debugDisplayTitle
            }
            
            self.nameNode?.attributedText = NSAttributedString(string: name, attributes: [
                .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                .foregroundColor: theme.list.itemPrimaryTextColor
            ])
            
            self.idNode?.attributedText = NSAttributedString(string: "ID: \(peer.id.id._internalGetInt64Value())", attributes: [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: theme.list.itemSecondaryTextColor
            ])
            
            let isPremium: Bool
            if case let .user(user) = peer {
                isPremium = user.isPremium
            } else {
                isPremium = false
            }
            
            if isPremium {
                self.badgeBgNode?.backgroundColor = UIColor(red: 0.42, green: 0.25, blue: 0.82, alpha: 1.0)
                self.badgeNode?.attributedText = NSAttributedString(string: "Premium", attributes: [
                    .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: UIColor.white
                ])
            } else {
                self.badgeBgNode?.backgroundColor = theme.list.itemBlocksSeparatorColor
                self.badgeNode?.attributedText = NSAttributedString(string: "Free", attributes: [
                    .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: theme.list.itemSecondaryTextColor
                ])
            }
        }
    }
}
