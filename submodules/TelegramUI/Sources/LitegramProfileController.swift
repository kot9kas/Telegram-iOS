import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
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

    private var profileGradientLayer: CAGradientLayer?
    private var profileSectionNode: ASDisplayNode?
    private var avatarNode: AvatarNode?
    private var nameNode: ASTextNode?
    private var idNode: ASTextNode?
    private var badgeBgNode: ASDisplayNode?
    private var badgeNode: ASTextNode?

    private var saveTrafficSectionNode: ASDisplayNode?
    private var saveTrafficTitleNode: ASTextNode?
    private var saveTrafficSubtitleNode: ASTextNode?
    private var saveTrafficSwitch: UISwitch?
    private var saveTrafficSepNode: ASDisplayNode?

    private var menuSectionNode: ASDisplayNode?
    private var tryButtonNode: ASButtonNode?

    private var currentPeer: EnginePeer?
    private var currentSubscription: LitegramSubscriptionStatus = .none
    private var lastLayout: ContainerViewLayout?

    private var litegramStrings: LitegramStrings {
        LitegramStrings(languageCode: self.presentationData.strings.primaryComponent.languageCode)
    }

    private struct MenuItem {
        let icon: UIImage?
        let title: String
        let subtitle: String
        let action: Selector
    }

    private var menuItems: [MenuItem] {
        [
            MenuItem(
                icon: renderSettingsIcon(name: "Item List/Icons/Key", backgroundColors: [UIColor(rgb: 0x5856d6)]),
                title: litegramStrings.chatsTitle,
                subtitle: litegramStrings.chatsSubtitle,
                action: #selector(chatsTapped)
            ),
            MenuItem(
                icon: renderSettingsIcon(name: "Settings/Menu/Proxy", backgroundColors: [UIColor(rgb: 0x34c759)]),
                title: litegramStrings.connectionTitle,
                subtitle: litegramStrings.connectionSubtitle,
                action: #selector(protectionTapped)
            ),
            MenuItem(
                icon: renderSettingsIcon(name: "Item List/Icons/Chat", backgroundColors: [UIColor(rgb: 0x007aff)]),
                title: litegramStrings.sessionTransferTitle,
                subtitle: litegramStrings.sessionTransferSubtitle,
                action: #selector(sessionTransferTapped)
            ),
            MenuItem(
                icon: renderSettingsIcon(name: "Item List/Icons/Support", backgroundColors: [UIColor(rgb: 0xff9500)]),
                title: litegramStrings.supportTitle,
                subtitle: "support@litegram.io",
                action: #selector(supportTapped)
            )
        ]
    }

    private var menuRowNodes: [(container: ASDisplayNode, icon: ASImageNode, title: ASTextNode, subtitle: ASTextNode, arrow: ASImageNode, sep: ASDisplayNode?)] = []

    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))

        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        self.navigationItem.title = "Litegram"

        self.tabBarItem.title = "Litegram"
        self.updateTabBarIcon()

        LitegramProxyController.shared.start(accountManager: context.sharedContext.accountManager)

        self.presentationDataDisposable = (context.sharedContext.presentationData
            |> deliverOnMainQueue).startStrict(next: { [weak self] presentationData in
                guard let self = self else { return }
                let previousTheme = self.presentationData.theme
                self.presentationData = presentationData
                if previousTheme !== presentationData.theme {
                    self.updateTheme()
                    self.updateTabBarIcon()
                }
                self.tabBarItem.title = "Litegram"
            })

        self.peerDisposable = (context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
            |> deliverOnMainQueue).startStrict(next: { [weak self] peer in
                guard let self = self else { return }
                self.currentPeer = peer
                if let p = peer, case let .user(u) = p {
                    let tgId = u.id.id._internalGetInt64Value()
                    LitegramDeviceToken.saveTelegramId("\(tgId)")
                    LitegramProxyController.shared.ensureRegistered(telegramId: tgId)
                }
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

    private func updateTabBarIcon() {
        let baseIcon = UIImage(bundleImageName: "Chat List/Tabs/IconLitegram")
        let iconColor = self.presentationData.theme.rootController.tabBar.iconColor
        let selectedColor = self.presentationData.theme.rootController.tabBar.selectedIconColor
        let tinted = generateTintedImage(image: baseIcon, color: iconColor)?.withRenderingMode(.alwaysOriginal)
        let selectedTinted = generateTintedImage(image: baseIcon, color: selectedColor)?.withRenderingMode(.alwaysOriginal)
        self.tabBarItem.image = tinted
        self.tabBarItem.selectedImage = selectedTinted
    }

    private func updateTheme() {
        self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: self.presentationData), transition: .immediate)
        if self.isNodeLoaded {
            let theme = self.presentationData.theme
            self.displayNode.backgroundColor = theme.list.blocksBackgroundColor
            self.profileGradientLayer?.colors = Self.gradientColors(from: theme.list.itemAccentColor)
            self.tryButtonNode?.backgroundColor = theme.list.itemAccentColor
            self.rebuildMenuColors()
            self.updateProfile()
        }
    }

    private static func gradientColors(from accent: UIColor) -> [CGColor] {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        accent.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let dark = UIColor(hue: h, saturation: min(s * 1.15, 1.0), brightness: max(b * 0.75, 0.0), alpha: a)
        let mid = UIColor(hue: h, saturation: s, brightness: b, alpha: a)
        let light = UIColor(hue: h, saturation: max(s * 0.7, 0.0), brightness: min(b * 1.2, 1.0), alpha: a)
        return [dark.cgColor, mid.cgColor, light.cgColor]
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
        fetchSubscriptionStatus()
        tryShowAd()
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.lastLayout = layout
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
        profileSection.clipsToBounds = true
        profileSection.cornerRadius = 16
        scrollNode?.addSubnode(profileSection)
        self.profileSectionNode = profileSection

        let gradient = CAGradientLayer()
        let accentColor = theme.list.itemAccentColor
        gradient.colors = Self.gradientColors(from: accentColor)
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        profileSection.layer.insertSublayer(gradient, at: 0)
        self.profileGradientLayer = gradient

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
        badgeBg.cornerRadius = 13
        profileSection.addSubnode(badgeBg)
        self.badgeBgNode = badgeBg

        let badge = ASTextNode()
        badge.textAlignment = .center
        badgeBg.addSubnode(badge)
        self.badgeNode = badge

        let saveTrafficSection = ASDisplayNode()
        saveTrafficSection.backgroundColor = theme.list.itemBlocksBackgroundColor
        saveTrafficSection.cornerRadius = 11
        scrollNode?.addSubnode(saveTrafficSection)
        self.saveTrafficSectionNode = saveTrafficSection

        let stTitle = ASTextNode()
        stTitle.attributedText = NSAttributedString(string: "Экономия трафика", attributes: [
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: theme.list.itemPrimaryTextColor
        ])
        saveTrafficSection.addSubnode(stTitle)
        self.saveTrafficTitleNode = stTitle

        let stSubtitle = ASTextNode()
        stSubtitle.attributedText = NSAttributedString(string: "Сжатие изображений и медиа", attributes: [
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: theme.list.itemSecondaryTextColor
        ])
        saveTrafficSection.addSubnode(stSubtitle)
        self.saveTrafficSubtitleNode = stSubtitle

        let toggle = UISwitch()
        toggle.isOn = LitegramConfig.isSaveTrafficEnabled
        toggle.addTarget(self, action: #selector(saveTrafficToggled(_:)), for: .valueChanged)
        saveTrafficSection.view.addSubview(toggle)
        self.saveTrafficSwitch = toggle

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
            iconNode.image = item.icon
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
            arrow.image = UIImage(bundleImageName: "Item List/DisclosureArrow")?.withRenderingMode(.alwaysTemplate)
            arrow.tintColor = theme.list.itemSecondaryTextColor
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

        let tryBtn = ASButtonNode()
        tryBtn.cornerRadius = 11
        tryBtn.clipsToBounds = true
        tryBtn.setTitle("⭐ Try all features", with: UIFont.systemFont(ofSize: 17, weight: .semibold), with: .white, for: .normal)
        tryBtn.backgroundColor = theme.list.itemAccentColor
        tryBtn.addTarget(self, action: #selector(tryAllFeaturesTapped), forControlEvents: .touchUpInside)
        scrollNode?.addSubnode(tryBtn)
        self.tryButtonNode = tryBtn

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
            self.profileGradientLayer?.frame = CGRect(origin: .zero, size: CGSize(width: cw, height: profileH))

            let ax = (cw - avatarSize) / 2
            self.avatarNode?.frame = CGRect(x: ax, y: profilePadTop, width: avatarSize, height: avatarSize)

            let ny = profilePadTop + avatarSize + avatarToName
            self.nameNode?.frame = CGRect(x: 36, y: ny, width: cw - 72, height: nameH)

            let iy = ny + nameH + nameToId
            self.idNode?.frame = CGRect(x: 36, y: iy, width: cw - 72, height: idH)

            let by = iy + idH + idToBadge
            let badgeTextSize = self.badgeNode?.measure(CGSize(width: cw, height: badgeH)) ?? CGSize(width: 40, height: 16)
            let badgeW = max(60, badgeTextSize.width + 24)
            self.badgeBgNode?.frame = CGRect(x: floor((cw - badgeW) / 2), y: by, width: badgeW, height: badgeH)
            self.badgeNode?.frame = CGRect(
                x: floor((badgeW - badgeTextSize.width) / 2),
                y: floor((badgeH - badgeTextSize.height) / 2),
                width: badgeTextSize.width,
                height: badgeTextSize.height
            )

            y += profileH + 16
        }

        let rowH: CGFloat = 56
        if let stSection = self.saveTrafficSectionNode {
            stSection.frame = CGRect(x: sideInset, y: y, width: cw, height: rowH)

            let textX: CGFloat = 16
            self.saveTrafficTitleNode?.frame = CGRect(x: textX, y: 9, width: cw - textX - 80, height: 22)
            self.saveTrafficSubtitleNode?.frame = CGRect(x: textX, y: 9 + 22 + 1, width: cw - textX - 80, height: 16)

            let switchSize = CGSize(width: 51, height: 31)
            self.saveTrafficSwitch?.frame = CGRect(
                x: cw - switchSize.width - 16,
                y: (rowH - switchSize.height) / 2,
                width: switchSize.width,
                height: switchSize.height
            )

            y += rowH + 12
        }

        let iconSize: CGFloat = 30
        let rowSideInset: CGFloat = 16
        let textX: CGFloat = rowSideInset + iconSize + 16

        if let menu = self.menuSectionNode {
            var totalH: CGFloat = 0
            for (i, row) in menuRowNodes.enumerated() {
                let menuRowH: CGFloat = 56
                row.container.frame = CGRect(x: 0, y: totalH, width: cw, height: menuRowH)

                row.icon.frame = CGRect(x: rowSideInset, y: (menuRowH - iconSize) / 2, width: iconSize, height: iconSize)

                let titleY: CGFloat = 9
                row.title.frame = CGRect(x: textX, y: titleY, width: cw - textX - 34, height: 22)
                row.subtitle.frame = CGRect(x: textX, y: titleY + 22 + 1, width: cw - textX - 34, height: 16)

                let arrowW: CGFloat = 7
                let arrowH: CGFloat = 12
                row.arrow.frame = CGRect(x: cw - 7 - arrowW, y: (menuRowH - arrowH) / 2, width: arrowW, height: arrowH)

                totalH += menuRowH

                if let sep = row.sep, i < menuRowNodes.count - 1 {
                    sep.frame = CGRect(x: textX - 1, y: totalH, width: cw - textX + 1 - 16, height: UIScreen.main.scale > 0 ? (1.0 / UIScreen.main.scale) : 0.5)
                    totalH += 1.0 / UIScreen.main.scale
                }
            }

            menu.frame = CGRect(x: sideInset, y: y, width: cw, height: totalH)
            y += totalH + 16
        }

        if let tryBtn = self.tryButtonNode {
            let btnH: CGFloat = 50
            tryBtn.frame = CGRect(x: sideInset, y: y, width: cw, height: btnH)
            y += btnH + 24
        }

        self.scrollNode?.view.contentSize = CGSize(width: width, height: y + bottomInset + 20)
    }

    // MARK: - Actions

    @objc private func chatsTapped() {
        let controller = litegramChatsController(context: self.context)
        self.push(controller)
    }

    @objc private func protectionTapped() {
        let connectionController = LitegramConnectionController(context: self.context)
        self.push(connectionController)
    }

    @objc private func sessionTransferTapped() {
        let actionSheet = ActionSheetController(presentationData: self.presentationData)
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: litegramStrings.sessionImport, color: .accent, action: { [weak self, weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    self?.presentImportPicker()
                }),
                ActionSheetButtonItem(title: litegramStrings.sessionExport, color: .accent, action: { [weak self, weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    self?.exportCurrentSession()
                })
            ]),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: self.presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        self.present(actionSheet, in: .window(.root))
    }

    private func presentImportPicker() {
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .import)
        }
        picker.delegate = self
        picker.allowsMultipleSelection = false
        self.view.window?.rootViewController?.present(picker, animated: true)
    }

    private func exportCurrentSession() {
        let _ = (accountBackupData(postbox: self.context.account.postbox)
        |> deliverOnMainQueue).startStandalone(next: { [weak self] backupData in
            guard let self else { return }
            guard let backupData else {
                let alert = ActionSheetController(presentationData: self.presentationData)
                alert.setItemGroups([
                    ActionSheetItemGroup(items: [
                        ActionSheetTextItem(title: self.litegramStrings.sessionExportNoData)
                    ]),
                    ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: self.presentationData.strings.Common_OK, color: .accent, font: .bold, action: { [weak alert] in
                            alert?.dismissAnimated()
                        })
                    ])
                ])
                self.present(alert, in: .window(.root))
                return
            }
            do {
                let fileURL = try LitegramSessionImporter.exportPyrogramSession(backupData: backupData)
                let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                activityVC.completionWithItemsHandler = { _, _, _, _ in
                    try? FileManager.default.removeItem(at: fileURL)
                }
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = self.view
                    popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                self.view.window?.rootViewController?.present(activityVC, animated: true)
            } catch {
                let alert = ActionSheetController(presentationData: self.presentationData)
                alert.setItemGroups([
                    ActionSheetItemGroup(items: [
                        ActionSheetTextItem(title: "\(self.litegramStrings.sessionExportError): \(error.localizedDescription)")
                    ]),
                    ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: self.presentationData.strings.Common_OK, color: .accent, font: .bold, action: { [weak alert] in
                            alert?.dismissAnimated()
                        })
                    ])
                ])
                self.present(alert, in: .window(.root))
            }
        })
    }

    @objc private func supportTapped() {
        let actionSheet = ActionSheetController(presentationData: self.presentationData)
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: "Поддержка в чате", color: .accent, action: { [weak self, weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    self?.openSupportChat()
                }),
                ActionSheetButtonItem(title: "Почта", color: .accent, action: { [weak self, weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    self?.openSupportEmail()
                })
            ]),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: self.presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        self.present(actionSheet, in: .window(.root))
    }

    private func openSupportChat() {
        self.context.sharedContext.openExternalUrl(
            context: self.context,
            urlContext: .generic,
            url: "https://t.me/Litegram_sup",
            forceExternal: false,
            presentationData: self.presentationData,
            navigationController: self.navigationController as? NavigationController,
            dismissInput: { }
        )
    }

    private func openSupportEmail() {
        self.context.sharedContext.openExternalUrl(
            context: self.context,
            urlContext: .generic,
            url: "mailto:support@litegram.io",
            forceExternal: true,
            presentationData: self.presentationData,
            navigationController: self.navigationController as? NavigationController,
            dismissInput: { }
        )
    }

    @objc private func saveTrafficToggled(_ sender: UISwitch) {
        LitegramConfig.isSaveTrafficEnabled = sender.isOn
        let _ = updateMediaDownloadSettingsInteractively(accountManager: self.context.sharedContext.accountManager, { settings in
            if sender.isOn {
                var updated = settings
                updated.cellular.enabled = false
                updated.wifi.enabled = false
                updated.downloadInBackground = false
                return updated
            } else {
                return MediaAutoDownloadSettings.defaultSettings
            }
        }).start()
    }

    @objc private func tryAllFeaturesTapped() {
        self.context.sharedContext.openExternalUrl(
            context: self.context,
            urlContext: .generic,
            url: "https://t.me/Litegram_robot?start=start",
            forceExternal: false,
            presentationData: self.presentationData,
            navigationController: self.navigationController as? NavigationController,
            dismissInput: { }
        )
    }

    private func fetchSubscriptionStatus() {
        LitegramProxyController.shared.refreshSubscription { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let status = LitegramConfig.subscriptionStatus
                self.currentSubscription = LitegramSubscriptionStatus(rawValue: status) ?? .none
                self.updateProfile()
            }
        }
    }

    private func tryShowAd() {
        let manager = LitegramAdManager.shared
        guard manager.shouldShowAd else { return }

        manager.fetchActiveAd { [weak self] ad in
            guard let self = self, let ad = ad else { return }
            DispatchQueue.main.async {
                self.showAdModal(ad)
            }
        }
    }

    private func showAdModal(_ ad: LitegramAdInfo) {
        let alert = UIAlertController(title: ad.title, message: ad.description, preferredStyle: .alert)

        if let link = ad.linkUrl, let url = URL(string: link) {
            alert.addAction(UIAlertAction(title: "Открыть", style: .default) { _ in
                UIApplication.shared.open(url)
            })
        }

        alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
        self.present(alert, animated: true)
        LitegramAdManager.shared.markAdShown()
    }

    // MARK: - Update

    private func rebuildMenuColors() {
        let theme = self.presentationData.theme
        self.saveTrafficSectionNode?.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.menuSectionNode?.backgroundColor = theme.list.itemBlocksBackgroundColor

        self.saveTrafficTitleNode?.attributedText = NSAttributedString(string: "Экономия трафика", attributes: [
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: theme.list.itemPrimaryTextColor
        ])
        self.saveTrafficSubtitleNode?.attributedText = NSAttributedString(string: "Сжатие изображений и медиа", attributes: [
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: theme.list.itemSecondaryTextColor
        ])

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
            row.arrow.tintColor = theme.list.itemSecondaryTextColor
            row.sep?.backgroundColor = theme.list.itemBlocksSeparatorColor
        }
    }

    private func updateProfile() {
        guard let peer = self.currentPeer else { return }

        self.avatarNode?.setPeer(
            context: self.context,
            theme: self.presentationData.theme,
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
            .foregroundColor: UIColor.white
        ])

        self.idNode?.attributedText = NSAttributedString(string: "ID: \(peer.id.id._internalGetInt64Value())", attributes: [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: UIColor.white.withAlphaComponent(0.7)
        ])

        let sub = self.currentSubscription
        let badgeFont = UIFont.systemFont(ofSize: 13, weight: .semibold)

        if sub.isActive {
            self.badgeBgNode?.backgroundColor = UIColor.white.withAlphaComponent(0.25)
            self.badgeNode?.attributedText = NSAttributedString(string: "⭐ Premium", attributes: [
                .font: badgeFont,
                .foregroundColor: UIColor.white
            ])
        } else {
            self.badgeBgNode?.backgroundColor = UIColor.black.withAlphaComponent(0.3)
            self.badgeNode?.attributedText = NSAttributedString(string: "Бесплатно", attributes: [
                .font: badgeFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.8)
            ])
        }

        if sub.isActive {
            self.tryButtonNode?.isHidden = true
        } else {
            self.tryButtonNode?.isHidden = false
        }

        if let layout = self.lastLayout {
            layoutNodes(width: layout.size.width, safeLeft: layout.safeInsets.left, safeRight: layout.safeInsets.right, bottomInset: layout.intrinsicInsets.bottom)
        }
    }
}

extension LitegramController: UIDocumentPickerDelegate {
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        do {
            let sessionData = try LitegramSessionImporter.parsePyrogramSession(at: url)
            let backupData = LitegramSessionImporter.makeBackupData(from: sessionData)
            let accountManager = self.context.sharedContext.accountManager
            let sharedContext = self.context.sharedContext

            let _ = accountManager.transaction({ transaction -> AccountRecordId in
                let id = transaction.createRecord([
                    .environment(AccountEnvironmentAttribute(environment: .production)),
                    .backupData(AccountBackupDataAttribute(data: backupData))
                ])
                transaction.setCurrentId(id)
                return id
            }).start(next: { id in
                Queue.mainQueue().async {
                    sharedContext.switchToAccount(id: id, fromSettingsController: nil, withChatListController: nil)
                }
            })
        } catch {
            let actionSheet = ActionSheetController(presentationData: self.presentationData)
            actionSheet.setItemGroups([
                ActionSheetItemGroup(items: [
                    ActionSheetTextItem(title: "\(self.litegramStrings.sessionImportError): \(error.localizedDescription)")
                ]),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: self.presentationData.strings.Common_OK, color: .accent, font: .bold, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                    })
                ])
            ])
            self.present(actionSheet, in: .window(.root))
        }
    }
}
