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
    private var badgeBgNode: ASDisplayNode?
    private var badgeNode: ASTextNode?
    
    private var menuSectionNode: ASDisplayNode?
    
    private var currentPeer: EnginePeer?
    private var currentSubscription: LitegramSubscriptionStatus = .none
    
    private struct MenuItem {
        let iconName: String
        let title: String
        let subtitle: String
        let action: Selector
    }
    
    private let menuItems: [MenuItem] = [
        MenuItem(iconName: "Settings/Menu/Proxy", title: "Protection", subtitle: "Proxy settings and connection", action: #selector(protectionTapped))
    ]
    
    private var menuRowNodes: [(container: ASDisplayNode, icon: ASImageNode, title: ASTextNode, subtitle: ASTextNode, arrow: ASImageNode, sep: ASDisplayNode?)] = []
    
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
                self.fetchSubscriptionStatus()
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
            self.rebuildMenuColors()
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
        if let scrollNode = self.scrollNode {
            transition.updateFrame(node: scrollNode, frame: CGRect(x: 0, y: navBarHeight, width: layout.size.width, height: layout.size.height - navBarHeight))
        }
        layoutNodes(width: layout.size.width, safeLeft: layout.safeInsets.left, safeRight: layout.safeInsets.right, bottomInset: layout.intrinsicInsets.bottom)
    }
    
    // MARK: - Setup
    
    private func setupNodes() {
        let theme = self.presentationData.theme
        
        let profileSection = ASDisplayNode()
        profileSection.backgroundColor = theme.list.itemBlocksBackgroundColor
        profileSection.cornerRadius = 11
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
        menuSection.cornerRadius = 11
        menuSection.clipsToBounds = true
        scrollNode?.addSubnode(menuSection)
        self.menuSectionNode = menuSection
        
        for (i, item) in menuItems.enumerated() {
            let container = ASDisplayNode()
            container.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: item.action))
            menuSection.addSubnode(container)
            
            let iconNode = ASImageNode()
            iconNode.displaysAsynchronously = false
            iconNode.image = UIImage(bundleImageName: item.iconName)
            iconNode.contentMode = .scaleAspectFit
            container.addSubnode(iconNode)
            
            let titleNode = ASTextNode()
            titleNode.attributedText = NSAttributedString(string: item.title, attributes: [
                .font: UIFont.systemFont(ofSize: 17),
                .foregroundColor: theme.list.itemPrimaryTextColor
            ])
            container.addSubnode(titleNode)
            
            let subtitleNode = ASTextNode()
            subtitleNode.attributedText = NSAttributedString(string: item.subtitle, attributes: [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: theme.list.itemSecondaryTextColor
            ])
            container.addSubnode(subtitleNode)
            
            let arrow = ASImageNode()
            arrow.displaysAsynchronously = false
            arrow.image = UIImage(bundleImageName: "Item List/DisclosureArrow")
            container.addSubnode(arrow)
            
            var sep: ASDisplayNode? = nil
            if i < menuItems.count - 1 {
                let s = ASDisplayNode()
                s.backgroundColor = theme.list.itemBlocksSeparatorColor
                menuSection.addSubnode(s)
                sep = s
            }
            
            menuRowNodes.append((container: container, icon: iconNode, title: titleNode, subtitle: subtitleNode, arrow: arrow, sep: sep))
        }
        
        updateProfile()
    }
    
    // MARK: - Layout
    
    private func layoutNodes(width: CGFloat, safeLeft: CGFloat, safeRight: CGFloat, bottomInset: CGFloat) {
        let sideInset: CGFloat = max(16.0, floor((width - 674.0) / 2.0))
        let cw = width - sideInset * 2
        var y: CGFloat = 16
        
        let avatarSize: CGFloat = 100
        let nameH: CGFloat = 34
        let idH: CGFloat = 20
        let badgeH: CGFloat = 26
        let profilePadTop: CGFloat = 24
        let profilePadBottom: CGFloat = 24
        let avatarToName: CGFloat = 9
        let nameToId: CGFloat = 1
        let idToBadge: CGFloat = 10
        let profileH = profilePadTop + avatarSize + avatarToName + nameH + nameToId + idH + idToBadge + badgeH + profilePadBottom
        
        if let section = self.profileSectionNode {
            section.frame = CGRect(x: sideInset, y: y, width: cw, height: profileH)
            
            let ax = (cw - avatarSize) / 2
            self.avatarNode?.frame = CGRect(x: ax, y: profilePadTop, width: avatarSize, height: avatarSize)
            
            let ny = profilePadTop + avatarSize + avatarToName
            self.nameNode?.frame = CGRect(x: 36, y: ny, width: cw - 72, height: nameH)
            
            let iy = ny + nameH + nameToId
            self.idNode?.frame = CGRect(x: 36, y: iy, width: cw - 72, height: idH)
            
            let by = iy + idH + idToBadge
            let badgeW: CGFloat = 80
            self.badgeBgNode?.frame = CGRect(x: (cw - badgeW) / 2, y: by, width: badgeW, height: badgeH)
            self.badgeNode?.frame = CGRect(x: 0, y: 0, width: badgeW, height: badgeH)
            
            y += profileH + 24
        }
        
        let iconSize: CGFloat = 29
        let rowSideInset: CGFloat = 16
        let textX: CGFloat = rowSideInset + iconSize + 16
        
        if let menu = self.menuSectionNode {
            var totalH: CGFloat = 0
            for (i, row) in menuRowNodes.enumerated() {
                let rowH: CGFloat = 56
                row.container.frame = CGRect(x: 0, y: totalH, width: cw, height: rowH)
                
                row.icon.frame = CGRect(x: rowSideInset, y: (rowH - iconSize) / 2, width: iconSize, height: iconSize)
                
                let titleY: CGFloat = 9
                row.title.frame = CGRect(x: textX, y: titleY, width: cw - textX - 34, height: 22)
                row.subtitle.frame = CGRect(x: textX, y: titleY + 22 + 1, width: cw - textX - 34, height: 16)
                
                let arrowW: CGFloat = 7
                let arrowH: CGFloat = 12
                row.arrow.frame = CGRect(x: cw - 7 - arrowW, y: (rowH - arrowH) / 2, width: arrowW, height: arrowH)
                
                totalH += rowH
                
                if let sep = row.sep, i < menuRowNodes.count - 1 {
                    sep.frame = CGRect(x: textX - 1, y: totalH, width: cw - textX + 1 - 16, height: UIScreen.main.scale > 0 ? (1.0 / UIScreen.main.scale) : 0.5)
                    totalH += 1.0 / UIScreen.main.scale
                }
            }
            
            menu.frame = CGRect(x: sideInset, y: y, width: cw, height: totalH)
            y += totalH + 24
        }
        
        self.scrollNode?.view.contentSize = CGSize(width: width, height: y + bottomInset + 20)
    }
    
    // MARK: - Actions
    
    @objc private func protectionTapped() {
        let connectionController = LitegramConnectionController(context: self.context)
        self.push(connectionController)
    }
    
    private func fetchSubscriptionStatus() {
        let api = LitegramProxyController.shared.api
        guard api.accessToken != nil else { return }
        api.getUserProfile { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case let .success(profile):
                    self.currentSubscription = profile.subscriptionStatus
                    self.updateProfile()
                case .failure:
                    break
                }
            }
        }
    }
    
    // MARK: - Update
    
    private func rebuildMenuColors() {
        let theme = self.presentationData.theme
        self.profileSectionNode?.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.menuSectionNode?.backgroundColor = theme.list.itemBlocksBackgroundColor
        
        for (i, row) in menuRowNodes.enumerated() {
            let item = menuItems[i]
            row.title.attributedText = NSAttributedString(string: item.title, attributes: [
                .font: UIFont.systemFont(ofSize: 17),
                .foregroundColor: theme.list.itemPrimaryTextColor
            ])
            row.subtitle.attributedText = NSAttributedString(string: item.subtitle, attributes: [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: theme.list.itemSecondaryTextColor
            ])
            row.sep?.backgroundColor = theme.list.itemBlocksSeparatorColor
        }
    }
    
    private func updateProfile() {
        let theme = self.presentationData.theme
        
        guard let peer = self.currentPeer else { return }
        
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
            .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: theme.list.itemPrimaryTextColor
        ])
        
        self.idNode?.attributedText = NSAttributedString(string: "ID: \(peer.id.id._internalGetInt64Value())", attributes: [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: theme.list.itemSecondaryTextColor
        ])
        
        let sub = self.currentSubscription
        let badgeText = sub.displayName
        let badgeFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
        
        if sub.isActive {
            self.badgeBgNode?.backgroundColor = UIColor(red: 0.42, green: 0.25, blue: 0.82, alpha: 1.0)
            self.badgeNode?.attributedText = NSAttributedString(string: badgeText, attributes: [
                .font: badgeFont,
                .foregroundColor: UIColor.white
            ])
        } else {
            self.badgeBgNode?.backgroundColor = theme.list.itemBlocksSeparatorColor
            self.badgeNode?.attributedText = NSAttributedString(string: badgeText, attributes: [
                .font: badgeFont,
                .foregroundColor: theme.list.itemSecondaryTextColor
            ])
        }
        
        if let bgFrame = self.badgeBgNode?.frame {
            let textH: CGFloat = 17
            let ty = (bgFrame.height - textH) / 2
            self.badgeNode?.frame = CGRect(x: 0, y: ty, width: bgFrame.width, height: textH)
        }
    }
}
