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

private final class LitegramServerRowNode: ASCellNode {
    private let flagNode = ASTextNode()
    private let titleNode = ASTextNode()
    private let checkNode = ASImageNode()
    private let separatorNode = ASDisplayNode()
    private let hasSeparator: Bool

    init(theme: PresentationTheme, title: String, countryCode: String, isSelected: Bool, hasSeparator: Bool) {
        self.hasSeparator = hasSeparator
        super.init()

        self.automaticallyManagesSubnodes = true
        self.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.selectionStyle = .none

        self.flagNode.attributedText = NSAttributedString(
            string: LitegramConnectionController.countryFlagStatic(countryCode),
            attributes: [.font: UIFont.systemFont(ofSize: 22)]
        )
        self.titleNode.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 17),
                .foregroundColor: theme.list.itemPrimaryTextColor
            ]
        )
        self.checkNode.displaysAsynchronously = false
        self.checkNode.image = UIImage(bundleImageName: "Chat/Context Menu/Check")
        self.checkNode.isHidden = !isSelected
        self.separatorNode.backgroundColor = theme.list.itemBlocksSeparatorColor
        self.separatorNode.isHidden = !hasSeparator
    }

    override func layout() {
        super.layout()
        let bounds = self.bounds
        self.flagNode.frame = CGRect(x: 16, y: floor((bounds.height - 28) / 2), width: 28, height: 28)
        self.titleNode.frame = CGRect(x: 52, y: floor((bounds.height - 22) / 2), width: max(0, bounds.width - 52 - 40), height: 22)
        self.checkNode.frame = CGRect(x: bounds.width - 30, y: floor((bounds.height - 16) / 2), width: 16, height: 16)
        if self.hasSeparator {
            let sepH = 1.0 / UIScreen.main.scale
            self.separatorNode.frame = CGRect(x: 52, y: bounds.height - sepH, width: max(0, bounds.width - 52 - 16), height: sepH)
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let spec = ASAbsoluteLayoutSpec()
        spec.children = [self.flagNode, self.titleNode, self.checkNode, self.separatorNode]
        return ASInsetLayoutSpec(insets: .zero, child: spec)
    }
}

public final class LitegramConnectionController: ViewController, ASTableDataSource, ASTableDelegate {
    private let context: AccountContext
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    private var proxySettingsDisposable: Disposable?
    private var connectionStatusDisposable: Disposable?

    private var currentProxySettings: ProxySettings?
    private var currentConnectionStatus: ConnectionStatus = .waitingForNetwork

    private var scrollNode: ASScrollNode?

    private var headerNode: ASDisplayNode?
    private var headerGradientLayer: CAGradientLayer?
    private var connectedAnimNode: AnimatedStickerNode?
    private var disconnectedAnimNode: AnimatedStickerNode?
    private var activeAnimNode: AnimatedStickerNode?
    private var headerTitleNode: ASTextNode?
    private var headerSubtitleNode: ASTextNode?
    private var headerBadgeBg: ASDisplayNode?
    private var headerBadgeNode: ASTextNode?

    private var serverSectionNode: ASDisplayNode?
    private var serverHeaderNode: ASTextNode?
    private var serversTableNode: ASTableNode?
    private var availableServers: [LitegramServerInfo] = []
    private var selectedServerIndex: Int = 0

    private var connectButtonNode: ASButtonNode?

    private var perksHeaderNode: ASTextNode?
    private var perksContainerNode: ASDisplayNode?
    private var perkNodes: [(bg: ASDisplayNode, icon: ASImageNode, title: ASTextNode, subtitle: ASTextNode, arrow: ASImageNode)] = []
    private var perkSepNodes: [ASDisplayNode] = []

    private var isConnecting = false
    private var lastAnimName: String?
    private var animSetupPending = false
    private var authObserver: NSObjectProtocol?
    private var fetchRetryWorkItem: DispatchWorkItem?
    private var lastServerDebugSignature: String?
    private let debugControllerInstanceId: String = UUID().uuidString
    private let serverRowHeight: CGFloat = 48

    private static let gradientColors: [UIColor] = [
        UIColor(red: 0.94, green: 0.41, blue: 0.13, alpha: 1.0),
        UIColor(red: 0.90, green: 0.29, blue: 0.22, alpha: 1.0),
        UIColor(red: 0.86, green: 0.22, blue: 0.29, alpha: 1.0),
        UIColor(red: 0.67, green: 0.29, blue: 0.77, alpha: 1.0),
        UIColor(red: 0.40, green: 0.42, blue: 1.00, alpha: 1.0),
        UIColor(red: 0.27, green: 0.57, blue: 1.00, alpha: 1.0),
        UIColor(red: 0.24, green: 0.70, blue: 0.43, alpha: 1.0)
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
        self.navigationItem.title = "Protection"
        // #region agent log
        self.debugLog(
            runId: "repro-2",
            hypothesisId: "H5",
            location: "LitegramController.swift:init",
            message: "controller init",
            data: [
                "controllerInstanceId": self.debugControllerInstanceId
            ]
        )
        // #endregion

        self.presentationDataDisposable = (context.sharedContext.presentationData
            |> deliverOnMainQueue).startStrict(next: { [weak self] presentationData in
                guard let self = self else { return }
                let previousTheme = self.presentationData.theme
                self.presentationData = presentationData
                if previousTheme !== presentationData.theme {
                    self.updateTheme()
                }
                self.navigationItem.title = "Protection"
            })

        self.proxySettingsDisposable = (context.sharedContext.accountManager.sharedData(keys: [SharedDataKeys.proxySettings])
            |> deliverOnMainQueue).startStrict(next: { [weak self] sharedData in
                guard let self = self else { return }
                self.currentProxySettings = sharedData.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? ProxySettings.defaultSettings
                // #region agent log
                self.debugLog(
                    runId: "repro-1",
                    hypothesisId: "H4",
                    location: "LitegramController.swift:proxySettingsDisposable",
                    message: "proxy settings update",
                    data: [
                        "enabled": self.currentProxySettings?.enabled ?? false,
                        "hasActiveServer": self.currentProxySettings?.activeServer != nil,
                        "activeHost": self.currentProxySettings?.activeServer?.host ?? "",
                        "availableServersCount": self.availableServers.count
                    ]
                )
                // #endregion
                self.applyServersFromActiveProxyIfNeeded()
                self.updateUI()
            })

        self.connectionStatusDisposable = (context.account.network.connectionStatus
            |> deliverOnMainQueue).startStrict(next: { [weak self] status in
                guard let self = self else { return }
                self.currentConnectionStatus = status
                self.updateUI()
            })

        self.authObserver = NotificationCenter.default.addObserver(
            forName: .litegramAuthDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.fetchServersWithToken()
        }

        fetchServers()
    }

    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // #region agent log
        self.debugLog(
            runId: "repro-2",
            hypothesisId: "H5",
            location: "LitegramController.swift:deinit",
            message: "controller deinit",
            data: [
                "controllerInstanceId": self.debugControllerInstanceId
            ]
        )
        // #endregion
        self.presentationDataDisposable?.dispose()
        self.proxySettingsDisposable?.dispose()
        self.connectionStatusDisposable?.dispose()
        self.fetchRetryWorkItem?.cancel()
        if let observer = self.authObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // #region agent log
        self.debugLog(
            runId: "repro-2",
            hypothesisId: "H5",
            location: "LitegramController.swift:viewDidAppear",
            message: "view did appear",
            data: [
                "controllerInstanceId": self.debugControllerInstanceId
            ]
        )
        // #endregion
        fetchServers()
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

    // MARK: - Fetch Servers

    private func fetchServers() {
        let proxy = LitegramProxyController.shared
        let api = proxy.api

        self.fetchRetryWorkItem?.cancel()
        let cachedServers = LitegramConfig.getCachedServers()
        // #region agent log
        self.debugLog(
            runId: "repro-1",
            hypothesisId: "H2",
            location: "LitegramController.swift:fetchServers",
            message: "fetchServers start",
            data: [
                "hasToken": api.accessToken != nil,
                "cachedServersCount": cachedServers.count,
                "hasActiveServer": self.currentProxySettings?.activeServer != nil
            ]
        )
        // #endregion
        if !cachedServers.isEmpty {
            self.applyServers(cachedServers)
        } else {
            self.applyServersFromActiveProxyIfNeeded()
        }

        if api.accessToken == nil, let tgId = LitegramDeviceToken.getTelegramId(), let tgValue = Int64(tgId) {
            proxy.ensureRegistered(telegramId: tgValue)
        }

        if api.accessToken == nil {
            scheduleFetchRetry(attempt: 0)
            return
        }
        fetchServersWithToken()
    }

    private func fetchServersWithToken() {
        let api = LitegramProxyController.shared.api
        guard api.accessToken != nil else { return }
        api.getProxyServers { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case let .success(servers) = result, !servers.isEmpty {
                    // #region agent log
                    self.debugLog(
                        runId: "repro-1",
                        hypothesisId: "H2",
                        location: "LitegramController.swift:fetchServersWithToken",
                        message: "api servers success",
                        data: ["serversCount": servers.count]
                    )
                    // #endregion
                    self.fetchRetryWorkItem?.cancel()
                    LitegramConfig.saveCachedServers(servers)
                    self.applyServers(servers)
                } else {
                    // #region agent log
                    let reason: String
                    switch result {
                    case .success:
                        reason = "empty_success"
                    case .failure:
                        reason = "failure"
                    }
                    self.debugLog(
                        runId: "repro-1",
                        hypothesisId: "H2",
                        location: "LitegramController.swift:fetchServersWithToken",
                        message: "api servers fallback path",
                        data: ["reason": reason, "cachedCount": LitegramConfig.getCachedServers().count]
                    )
                    // #endregion
                    let cached = LitegramConfig.getCachedServers()
                    if !cached.isEmpty {
                        self.applyServers(cached)
                    } else {
                        self.applyServersFromActiveProxyIfNeeded()
                    }
                }
            }
        }
    }

    private func applyServers(_ servers: [LitegramServerInfo]) {
        guard !servers.isEmpty else { return }
        self.availableServers = servers
        if let savedHost = LitegramConfig.selectedServerHost,
           let idx = servers.firstIndex(where: { $0.host == savedHost }) {
            self.selectedServerIndex = idx
        } else {
            self.selectedServerIndex = 0
        }
        if self.serverSectionNode != nil {
            // #region agent log
            self.debugLog(
                runId: "repro-1",
                hypothesisId: "H1",
                location: "LitegramController.swift:applyServers",
                message: "applyServers",
                data: [
                    "serversCount": servers.count,
                    "firstHost": servers.first?.host ?? "",
                    "serverSectionExists": self.serverSectionNode != nil,
                    "isNodeLoaded": self.isNodeLoaded
                ]
            )
            // #endregion
            self.rebuildServerRows()
            self.updateUI()
            self.view.setNeedsLayout()
        }
    }

    private func applyServersFromActiveProxyIfNeeded() {
        guard self.availableServers.isEmpty else { return }
        guard let active = self.currentProxySettings?.activeServer else { return }
        
        let secret = self.extractMtpSecretHex(from: active.connection)
        let fallback = LitegramServerInfo(
            host: active.host,
            port: Int(active.port),
            secret: secret ?? "",
            name: active.host,
            country: ""
        )
        self.applyServers([fallback])
    }

    private func extractMtpSecretHex(from connection: Any) -> String? {
        func dataToHex(_ data: Data) -> String {
            data.map { String(format: "%02x", $0) }.joined()
        }
        
        let mirror = Mirror(reflecting: connection)
        for child in mirror.children {
            if let data = child.value as? Data {
                return dataToHex(data)
            }
            let nested = Mirror(reflecting: child.value)
            for inner in nested.children {
                if let data = inner.value as? Data {
                    return dataToHex(data)
                }
            }
        }
        return nil
    }

    private func scheduleFetchRetry(attempt: Int) {
        guard attempt < 12 else { return }
        let delay = min(0.5 + Double(attempt) * 0.25, 3.0)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if LitegramProxyController.shared.api.accessToken != nil {
                self.fetchServersWithToken()
            } else {
                self.scheduleFetchRetry(attempt: attempt + 1)
            }
        }
        self.fetchRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
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
            UIColor(red: 0.42, green: 0.25, blue: 0.82, alpha: 1.0).cgColor,
            UIColor(red: 0.55, green: 0.35, blue: 0.88, alpha: 1.0).cgColor,
            UIColor(red: 0.75, green: 0.55, blue: 0.92, alpha: 1.0).cgColor
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        header.layer.insertSublayer(gradient, at: 0)
        self.headerGradientLayer = gradient

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

        let hBadgeBg = ASDisplayNode()
        hBadgeBg.cornerRadius = 11
        header.addSubnode(hBadgeBg)
        self.headerBadgeBg = hBadgeBg

        let hBadge = ASTextNode()
        hBadge.textAlignment = .center
        hBadgeBg.addSubnode(hBadge)
        self.headerBadgeNode = hBadge

        let serverSection = ASDisplayNode()
        serverSection.backgroundColor = theme.list.itemBlocksBackgroundColor
        serverSection.cornerRadius = 11
        serverSection.clipsToBounds = true
        scrollNode?.addSubnode(serverSection)
        self.serverSectionNode = serverSection

        let serversTable = ASTableNode(style: .plain)
        serversTable.view.separatorStyle = .none
        serversTable.backgroundColor = .clear
        serversTable.dataSource = self
        serversTable.delegate = self
        serverSection.addSubnode(serversTable)
        self.serversTableNode = serversTable

        let serverHeader = ASTextNode()
        serverHeader.attributedText = NSAttributedString(string: "SERVERS", attributes: [
            .font: UIFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: theme.list.itemSecondaryTextColor,
            .kern: 0.5 as NSNumber
        ])
        scrollNode?.addSubnode(serverHeader)
        self.serverHeaderNode = serverHeader

        let button = ASButtonNode()
        button.cornerRadius = 11
        button.clipsToBounds = true
        button.addTarget(self, action: #selector(actionButtonTapped), forControlEvents: .touchUpInside)
        scrollNode?.addSubnode(button)
        self.connectButtonNode = button

        let perksHeader = ASTextNode()
        perksHeader.attributedText = NSAttributedString(string: "WHAT'S INCLUDED", attributes: [
            .font: UIFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: theme.list.itemSecondaryTextColor,
            .kern: 0.5 as NSNumber
        ])
        scrollNode?.addSubnode(perksHeader)
        self.perksHeaderNode = perksHeader

        let perksContainer = ASDisplayNode()
        perksContainer.backgroundColor = theme.list.itemBlocksBackgroundColor
        perksContainer.cornerRadius = 11
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

        if !self.availableServers.isEmpty {
            self.rebuildServerRows()
        } else {
            self.applyServersFromActiveProxyIfNeeded()
            if !self.availableServers.isEmpty {
                self.rebuildServerRows()
            }
        }

        updateUI()
    }

    private func rebuildServerRows() {
        self.serversTableNode?.reloadData()
        
        // #region agent log
        self.debugLog(
            runId: "repro-1",
            hypothesisId: "H3",
            location: "LitegramController.swift:rebuildServerRows",
            message: "rows rebuilt",
            data: [
                "availableServersCount": self.availableServers.count,
                    "rowNodesCount": self.availableServers.count
            ]
        )
        // #endregion
    }

    private func countryFlag(_ code: String) -> String {
        return Self.countryFlagStatic(code)
    }

    fileprivate static func countryFlagStatic(_ code: String) -> String {
        guard code.count == 2 else { return "🌍" }
        let base: UInt32 = 0x1F1E6
        let aVal: UInt32 = 65
        let chars = code.uppercased().unicodeScalars.compactMap { scalar -> Character? in
            guard let s = Unicode.Scalar(base + scalar.value - aVal) else { return nil }
            return Character(s)
        }
        return chars.count == 2 ? String(chars) : "🌍"
    }

    // MARK: - Layout

    private func layoutNodes(width: CGFloat, bottomInset: CGFloat) {
        let sideInset: CGFloat = max(16.0, floor((width - 674.0) / 2.0))
        let cw = width - sideInset * 2
        var y: CGFloat = 12

        let animSize: CGFloat = 80
        let titleH: CGFloat = 34
        let subtitleH: CGFloat = 20
        let badgeRowH: CGFloat = 22
        let headerH: CGFloat = animSize + titleH + subtitleH + badgeRowH + 58

        if let header = self.headerNode {
            header.frame = CGRect(x: sideInset, y: y, width: cw, height: headerH)
            self.headerGradientLayer?.frame = CGRect(origin: .zero, size: CGSize(width: cw, height: headerH))

            let contentH = animSize + 8 + titleH + 2 + subtitleH + 6 + badgeRowH
            let topPad = (headerH - contentH) / 2
            let animFrame = CGRect(x: (cw - animSize) / 2, y: topPad, width: animSize, height: animSize)
            let animLayoutSize = CGSize(width: animSize, height: animSize)
            self.connectedAnimNode?.frame = animFrame
            self.connectedAnimNode?.updateLayout(size: animLayoutSize)
            self.disconnectedAnimNode?.frame = animFrame
            self.disconnectedAnimNode?.updateLayout(size: animLayoutSize)

            let ty = topPad + animSize + 8
            self.headerTitleNode?.frame = CGRect(x: 0, y: ty, width: cw, height: titleH)
            self.headerSubtitleNode?.frame = CGRect(x: 36, y: ty + titleH + 2, width: cw - 72, height: subtitleH)

            let badgeY = ty + titleH + 2 + subtitleH + 6
            let badgeTextSize = self.headerBadgeNode?.measure(CGSize(width: cw, height: badgeRowH)) ?? CGSize(width: 40, height: 14)
            let badgeW = max(50, badgeTextSize.width + 16)
            self.headerBadgeBg?.frame = CGRect(x: floor((cw - badgeW) / 2), y: badgeY, width: badgeW, height: badgeRowH)
            self.headerBadgeNode?.frame = CGRect(
                x: floor((badgeW - badgeTextSize.width) / 2),
                y: floor((badgeRowH - badgeTextSize.height) / 2),
                width: badgeTextSize.width,
                height: badgeTextSize.height
            )

            y += headerH + 12
        }

        if !availableServers.isEmpty {
            self.serverHeaderNode?.frame = CGRect(x: sideInset + 16, y: y, width: cw, height: 18)
            y += 18 + 7

            let sepH = 1.0 / UIScreen.main.scale
            let totalH = CGFloat(availableServers.count) * self.serverRowHeight + CGFloat(max(0, availableServers.count - 1)) * sepH
            self.serverSectionNode?.frame = CGRect(x: sideInset, y: y, width: cw, height: totalH)
            self.serversTableNode?.frame = CGRect(x: 0, y: 0, width: cw, height: totalH)
            y += totalH + 16
        } else {
            self.serverHeaderNode?.frame = .zero
            self.serverSectionNode?.frame = CGRect(x: sideInset, y: y, width: cw, height: 0)
            self.serversTableNode?.frame = .zero
        }
        
        let signature = "\(availableServers.count)|\(availableServers.count)|\(Int(self.serverSectionNode?.frame.height ?? 0))"
        if signature != self.lastServerDebugSignature {
            self.lastServerDebugSignature = signature
            // #region agent log
            self.debugLog(
                runId: "repro-2",
                hypothesisId: "H6",
                location: "LitegramController.swift:layoutNodes",
                message: "server layout snapshot",
                data: [
                    "controllerInstanceId": self.debugControllerInstanceId,
                    "availableServersCount": self.availableServers.count,
                    "rowNodesCount": self.availableServers.count,
                    "serverSectionHeight": self.serverSectionNode?.frame.height ?? 0,
                    "serverHeaderHidden": self.serverHeaderNode?.frame == .zero,
                    "serverSectionHidden": self.serverSectionNode?.isHidden ?? false,
                    "serverSectionAlpha": self.serverSectionNode?.alpha ?? -1,
                    "serverSectionSubnodes": self.serverSectionNode?.subnodes?.count ?? 0
                ]
            )
            // #endregion
        }

        if let btn = self.connectButtonNode {
            btn.frame = CGRect(x: sideInset, y: y, width: cw, height: 50)
            y += 50 + 24
        }

        self.perksHeaderNode?.frame = CGRect(x: sideInset + 16, y: y, width: cw, height: 18)
        y += 7 + 18 + 7

        if let _ = self.perksContainerNode {
            let perkRowH: CGFloat = 56
            let sepH = 1.0 / UIScreen.main.scale
            let count = perkNodes.count
            let totalH = CGFloat(count) * perkRowH + CGFloat(perkSepNodes.count) * sepH
            self.perksContainerNode?.frame = CGRect(x: sideInset, y: y, width: cw, height: totalH)

            let iconSize: CGFloat = 29
            let iconInset: CGFloat = 16
            let textX: CGFloat = iconInset + iconSize + 16
            let arrowW: CGFloat = 7
            let arrowH: CGFloat = 12

            var fy: CGFloat = 0
            for i in 0..<count {
                let node = perkNodes[i]

                node.bg.frame = CGRect(x: iconInset, y: fy + (perkRowH - iconSize) / 2, width: iconSize, height: iconSize)
                node.icon.frame = CGRect(x: 4, y: 4, width: iconSize - 8, height: iconSize - 8)

                let perkTitleY = fy + 8
                node.title.frame = CGRect(x: textX, y: perkTitleY, width: cw - textX - 34, height: 22)
                node.subtitle.frame = CGRect(x: textX, y: perkTitleY + 22 + 1, width: cw - textX - 34, height: 16)

                node.arrow.frame = CGRect(x: cw - 7 - arrowW, y: fy + (perkRowH - arrowH) / 2, width: arrowW, height: arrowH)

                fy += perkRowH
                if i < perkSepNodes.count {
                    perkSepNodes[i].frame = CGRect(x: textX - 1, y: fy, width: cw - textX + 1 - 16, height: sepH)
                    fy += sepH
                }
            }
            y += totalH + 24
        }

        self.scrollNode?.view.contentSize = CGSize(width: width, height: y + bottomInset + 20)
    }

    // MARK: - Actions

    @objc private func headerTapped() {
        self.activeAnimNode?.playOnce()
    }

    private func selectServer(at index: Int) {
        guard index >= 0 && index < self.availableServers.count else { return }
        self.selectedServerIndex = index
        let server = self.availableServers[index]
        LitegramConfig.selectedServerHost = server.host
        LitegramProxyController.shared.applyServer(server)
        self.serversTableNode?.reloadData()
    }

    @objc private func actionButtonTapped() {
        guard !self.isConnecting else { return }
        let settings = self.currentProxySettings ?? ProxySettings.defaultSettings
        if settings.enabled && settings.activeServer != nil {
            LitegramProxyController.shared.disconnect()
        } else {
            self.isConnecting = true
            if !availableServers.isEmpty && selectedServerIndex < availableServers.count {
                LitegramProxyController.shared.applyServer(availableServers[selectedServerIndex])
            } else {
                LitegramProxyController.shared.reconnect()
            }
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
                btnColor = UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
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
                btnColor = UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
            case .waitingForNetwork:
                titleStr = "Waiting for network..."
                subtitleStr = "No internet connection"
                animName = "media_forbidden"
                btnTitle = "Disconnect"
                btnColor = UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
            }
        } else {
            self.isConnecting = false
            titleStr = "Disconnected"
            subtitleStr = "Tap Connect to enable proxy"
            animName = "media_forbidden"
            btnTitle = "Connect"
            btnColor = UIColor(red: 0.42, green: 0.25, blue: 0.82, alpha: 1.0)
        }

        self.headerTitleNode?.attributedText = NSAttributedString(string: titleStr, attributes: [
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: UIColor.white
        ])

        self.headerSubtitleNode?.attributedText = NSAttributedString(string: subtitleStr, attributes: [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: UIColor.white.withAlphaComponent(0.85)
        ])

        let subActive = LitegramConfig.isSubscriptionActive
        let badgeFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
        if subActive {
            self.headerBadgeBg?.backgroundColor = UIColor.white.withAlphaComponent(0.25)
            self.headerBadgeNode?.attributedText = NSAttributedString(string: "⭐ Premium", attributes: [
                .font: badgeFont, .foregroundColor: UIColor.white
            ])
        } else {
            self.headerBadgeBg?.backgroundColor = UIColor.black.withAlphaComponent(0.3)
            self.headerBadgeNode?.attributedText = NSAttributedString(string: "Free", attributes: [
                .font: badgeFont, .foregroundColor: UIColor.white.withAlphaComponent(0.8)
            ])
        }

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

        self.connectButtonNode?.setTitle(btnTitle, with: UIFont.systemFont(ofSize: 17, weight: .semibold), with: .white, for: .normal)
        self.connectButtonNode?.backgroundColor = btnColor
    }

    public func numberOfSections(in tableNode: ASTableNode) -> Int {
        return 1
    }

    public func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        return self.availableServers.count
    }

    public func tableNode(_ tableNode: ASTableNode, constrainedSizeForRowAt indexPath: IndexPath) -> ASSizeRange {
        let width = max(0, tableNode.bounds.width)
        let height = self.serverRowHeight + (indexPath.row < self.availableServers.count - 1 ? (1.0 / UIScreen.main.scale) : 0)
        let size = CGSize(width: width, height: height)
        return ASSizeRange(min: size, max: size)
    }

    public func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        let server = self.availableServers[indexPath.row]
        let isSelected = indexPath.row == self.selectedServerIndex
        let hasSeparator = indexPath.row < self.availableServers.count - 1
        let label = server.name.isEmpty ? server.host : "\(server.name) (\(server.country.uppercased()))"
        let theme = self.presentationData.theme
        return {
            return LitegramServerRowNode(
                theme: theme,
                title: label,
                countryCode: server.country,
                isSelected: isSelected,
                hasSeparator: hasSeparator
            )
        }
    }

    public func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        self.selectServer(at: indexPath.row)
    }
    
    private func debugLog(
        runId: String,
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: Any]
    ) {
        guard let url = URL(string: "http://127.0.0.1:7748/ingest/e6d1595d-3e23-4700-905a-6ebc4c266571") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("fff99e", forHTTPHeaderField: "X-Debug-Session-Id")
        
        var payload: [String: Any] = [
            "sessionId": "fff99e",
            "runId": runId,
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000.0)
        ]
        payload["id"] = "log_\(payload["timestamp"] ?? 0)_\(UUID().uuidString)"
        
        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
        request.httpBody = body
        URLSession.shared.dataTask(with: request).resume()
    }
}
