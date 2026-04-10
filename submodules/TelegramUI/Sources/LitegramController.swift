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

public final class LitegramConnectionController: ViewController, UITableViewDataSource, UITableViewDelegate {
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
    private var offAnimNode: AnimatedStickerNode?
    private var activeAnimNode: AnimatedStickerNode?
    private var headerTitleNode: ASTextNode?
    private var headerSubtitleNode: ASTextNode?
    private var headerBadgeBg: ASDisplayNode?
    private var headerBadgeNode: ASTextNode?

    private var serverSectionNode: ASDisplayNode?
    private var serverHeaderNode: ASTextNode?
    private var serversTableView: UITableView?
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
    private let serverRowHeight: CGFloat = 48.0
    private static let serverCellReuseId = "LitegramServerCell"

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
        ("Premium/Perk/Speed", "Быстрый и стабильный", "Высокоскоростной прокси без ограничений"),
        ("Premium/Perk/NoForward", "Усиленная приватность", "Ваш трафик зашифрован от начала до конца"),
        ("Premium/Perk/NoAds", "Доступ к заблокированному", "Обход региональных ограничений"),
        ("Premium/Perk/Limits", "Без лимитов скорости", "Безлимитная пропускная способность"),
        ("Premium/Perk/Chat", "Автопереподключение", "Остаётся на связи даже при нестабильной сети"),
        ("Premium/Perk/Status", "Множество серверов", "Выбирайте серверы по всему миру"),
        ("Premium/Perk/Translation", "Простота использования", "Подключение в одно нажатие")
    ]

    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))

        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        self.navigationItem.title = "Соединение"

        self.presentationDataDisposable = (context.sharedContext.presentationData
            |> deliverOnMainQueue).startStrict(next: { [weak self] presentationData in
                guard let self = self else { return }
                let previousTheme = self.presentationData.theme
                self.presentationData = presentationData
                if previousTheme !== presentationData.theme {
                    self.updateTheme()
                }
                self.navigationItem.title = "Соединение"
            })

        self.proxySettingsDisposable = (context.sharedContext.accountManager.sharedData(keys: [SharedDataKeys.proxySettings])
            |> deliverOnMainQueue).startStrict(next: { [weak self] sharedData in
                guard let self = self else { return }
                self.currentProxySettings = sharedData.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? ProxySettings.defaultSettings
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
            let theme = self.presentationData.theme
            self.displayNode.backgroundColor = theme.list.blocksBackgroundColor
            self.headerGradientLayer?.colors = Self.gradientColorsFromAccent(theme.list.itemAccentColor)
            self.updateUI()
        }
    }

    private static func gradientColorsFromAccent(_ accent: UIColor) -> [CGColor] {
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
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        fetchServers()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.connectedAnimNode?.visibility = true
            self.disconnectedAnimNode?.visibility = true
            self.offAnimNode?.visibility = true
            if self.activeAnimNode === self.offAnimNode {
                self.activeAnimNode?.playLoop()
            } else {
                self.activeAnimNode?.playOnce()
            }
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
                self.offAnimNode?.visibility = true
                if self.activeAnimNode === self.offAnimNode {
                    self.activeAnimNode?.playLoop()
                } else {
                    self.activeAnimNode?.playOnce()
                }
            }
        }
    }

    // MARK: - Fetch Servers

    private func fetchServers() {
        let proxy = LitegramProxyController.shared
        let api = proxy.api

        self.fetchRetryWorkItem?.cancel()
        let cachedServers = LitegramConfig.getCachedServers()
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
                    self.fetchRetryWorkItem?.cancel()
                    LitegramConfig.saveCachedServers(servers)
                    self.applyServers(servers)
                } else {
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
        let accentColor = theme.list.itemAccentColor
        gradient.colors = Self.gradientColorsFromAccent(accentColor)
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

        let offAnim = DefaultAnimatedStickerNodeImpl()
        offAnim.automaticallyLoadFirstFrame = true
        offAnim.setup(source: AnimatedStickerNodeLocalFileSource(name: "litegram_disconnected"), width: pixelSize, height: pixelSize, playbackMode: .loop, mode: .direct(cachePathPrefix: nil))
        offAnim.isHidden = true
        header.addSubnode(offAnim)
        self.offAnimNode = offAnim

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

        let serversTable = UITableView(frame: .zero, style: .plain)
        serversTable.backgroundColor = .clear
        serversTable.separatorStyle = .none
        serversTable.showsVerticalScrollIndicator = false
        serversTable.alwaysBounceVertical = false
        serversTable.dataSource = self
        serversTable.delegate = self
        serversTable.rowHeight = self.serverRowHeight
        serversTable.estimatedRowHeight = self.serverRowHeight
        serversTable.register(UITableViewCell.self, forCellReuseIdentifier: Self.serverCellReuseId)
        serverSection.view.addSubview(serversTable)
        self.serversTableView = serversTable

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
            arrow.image = UIImage(bundleImageName: "Item List/DisclosureArrow")?.withRenderingMode(.alwaysTemplate)
            arrow.tintColor = theme.list.itemSecondaryTextColor
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
        self.serversTableView?.reloadData()
    }

    private func countryFlag(_ code: String) -> String {
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
            self.offAnimNode?.frame = animFrame
            self.offAnimNode?.updateLayout(size: animLayoutSize)

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
            self.serversTableView?.frame = CGRect(x: 0, y: 0, width: cw, height: totalH)
            y += totalH + 16
        } else {
            self.serverHeaderNode?.frame = .zero
            self.serverSectionNode?.frame = CGRect(x: sideInset, y: y, width: cw, height: 0)
            self.serversTableView?.frame = .zero
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
        if self.activeAnimNode === self.offAnimNode {
            self.activeAnimNode?.playLoop()
        } else {
            self.activeAnimNode?.playOnce()
        }
    }

    private func selectServer(at index: Int) {
        guard index >= 0 && index < self.availableServers.count else { return }
        self.selectedServerIndex = index
        let server = self.availableServers[index]
        LitegramConfig.selectedServerHost = server.host
        LitegramProxyController.shared.applyServer(server)
        self.serversTableView?.reloadData()
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
                let alert = UIAlertController(title: "Ошибка подключения", message: "Не удалось подключиться к прокси-серверу. Проверьте интернет-соединение и попробуйте снова.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "ОК", style: .default))
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
                titleStr = "Подключено"
                subtitleStr = "Безопасное соединение через прокси"
                animName = "change_number"
                btnTitle = "Отключить"
                btnColor = UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
            case .connecting:
                titleStr = "Подключение..."
                subtitleStr = "Устанавливаем безопасное соединение"
                animName = "media_forbidden"
                btnTitle = "Подключение..."
                btnColor = theme.list.itemAccentColor.withAlphaComponent(0.6)
            case .updating:
                titleStr = "Обновление..."
                subtitleStr = "Обновляем соединение"
                animName = "change_number"
                btnTitle = "Отключить"
                btnColor = UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
            case .waitingForNetwork:
                titleStr = "Ожидание сети..."
                subtitleStr = "Нет интернет-соединения"
                animName = "media_forbidden"
                btnTitle = "Отключить"
                btnColor = UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
            }
        } else {
            self.isConnecting = false
            titleStr = "Отключено"
            subtitleStr = "Нажмите Подключить для включения прокси"
            animName = "litegram_disconnected"
            btnTitle = "Подключить"
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

        let subActive = LitegramConfig.isSubscriptionActive
        let badgeFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
        if subActive {
            self.headerBadgeBg?.backgroundColor = UIColor.white.withAlphaComponent(0.25)
            self.headerBadgeNode?.attributedText = NSAttributedString(string: "⭐ Premium", attributes: [
                .font: badgeFont, .foregroundColor: UIColor.white
            ])
        } else {
            self.headerBadgeBg?.backgroundColor = UIColor.black.withAlphaComponent(0.3)
            self.headerBadgeNode?.attributedText = NSAttributedString(string: "Бесплатно", attributes: [
                .font: badgeFont, .foregroundColor: UIColor.white.withAlphaComponent(0.8)
            ])
        }

        let targetNode: AnimatedStickerNode?
        if animName == "change_number" {
            targetNode = self.connectedAnimNode
        } else if animName == "litegram_disconnected" {
            targetNode = self.offAnimNode
        } else {
            targetNode = self.disconnectedAnimNode
        }

        if self.activeAnimNode !== targetNode || self.lastAnimName != animName {
            self.lastAnimName = animName
            self.connectedAnimNode?.isHidden = true
            self.disconnectedAnimNode?.isHidden = true
            self.offAnimNode?.isHidden = true
            targetNode?.isHidden = false
            self.activeAnimNode = targetNode
            self.animSetupPending = true
            targetNode?.visibility = true
            if targetNode === self.offAnimNode {
                targetNode?.playLoop()
            } else {
                targetNode?.playOnce()
            }
        }

        self.connectButtonNode?.setTitle(btnTitle, with: UIFont.systemFont(ofSize: 17, weight: .semibold), with: .white, for: .normal)
        self.connectButtonNode?.backgroundColor = btnColor

        self.serverSectionNode?.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.perksContainerNode?.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.serverHeaderNode?.attributedText = NSAttributedString(string: "SERVERS", attributes: [
            .font: UIFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: theme.list.itemSecondaryTextColor,
            .kern: 0.5 as NSNumber
        ])
        self.perksHeaderNode?.attributedText = NSAttributedString(string: "WHAT'S INCLUDED", attributes: [
            .font: UIFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: theme.list.itemSecondaryTextColor,
            .kern: 0.5 as NSNumber
        ])
        for (i, node) in self.perkNodes.enumerated() {
            let perk = Self.perks[i]
            node.title.attributedText = NSAttributedString(string: perk.title, attributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .regular),
                .foregroundColor: theme.list.itemPrimaryTextColor
            ])
            node.subtitle.attributedText = NSAttributedString(string: perk.subtitle, attributes: [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: theme.list.itemSecondaryTextColor
            ])
            node.arrow.tintColor = theme.list.itemSecondaryTextColor
        }
        for sep in self.perkSepNodes {
            sep.backgroundColor = theme.list.itemBlocksSeparatorColor
        }
        self.serversTableView?.reloadData()
    }

    public func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.availableServers.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let theme = self.presentationData.theme
        let server = self.availableServers[indexPath.row]
        let isSelected = indexPath.row == self.selectedServerIndex
        let label = server.name.isEmpty ? server.host : "\(server.name) (\(server.country.uppercased()))"

        let cell = tableView.dequeueReusableCell(withIdentifier: Self.serverCellReuseId, for: indexPath)
        cell.backgroundColor = theme.list.itemBlocksBackgroundColor
        cell.selectionStyle = .none
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }

        let flagLabel = UILabel(frame: CGRect(x: 16, y: 10, width: 28, height: 28))
        flagLabel.font = UIFont.systemFont(ofSize: 22)
        flagLabel.text = countryFlag(server.country)
        flagLabel.backgroundColor = .clear
        cell.contentView.addSubview(flagLabel)

        let titleLabel = UILabel(frame: CGRect(x: 52, y: 13, width: max(0, tableView.bounds.width - 92), height: 22))
        titleLabel.font = UIFont.systemFont(ofSize: 17)
        titleLabel.textColor = theme.list.itemPrimaryTextColor
        titleLabel.text = label
        titleLabel.backgroundColor = .clear
        cell.contentView.addSubview(titleLabel)

        let checkView = UIImageView(frame: CGRect(x: max(0, tableView.bounds.width - 30), y: 16, width: 16, height: 16))
        checkView.image = UIImage(bundleImageName: "Chat/Context Menu/Check")?.withRenderingMode(.alwaysTemplate)
        checkView.tintColor = theme.list.itemAccentColor
        checkView.isHidden = !isSelected
        cell.contentView.addSubview(checkView)

        if indexPath.row < self.availableServers.count - 1 {
            let sepH = 1.0 / UIScreen.main.scale
            let sep = UIView(frame: CGRect(x: 52, y: self.serverRowHeight - sepH, width: max(0, tableView.bounds.width - 68), height: sepH))
            sep.backgroundColor = theme.list.itemBlocksSeparatorColor
            cell.contentView.addSubview(sep)
        }

        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.selectServer(at: indexPath.row)
    }
}
