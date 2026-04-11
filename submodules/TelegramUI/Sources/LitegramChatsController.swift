import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import Litegram
import LocalAuthentication
import AnimatedStickerNode
import TelegramAnimatedStickerNode

private final class LitegramChatsArguments {
    let context: AccountContext
    let toggleBiometric: (Bool) -> Void
    let openAutolock: () -> Void
    let addPassword: () -> Void
    let openChat: (Int64) -> Void
    let openFolder: (Int32) -> Void
    let removeChat: (Int64) -> Void
    let removeFolder: (Int32) -> Void

    init(
        context: AccountContext,
        toggleBiometric: @escaping (Bool) -> Void,
        openAutolock: @escaping () -> Void,
        addPassword: @escaping () -> Void,
        openChat: @escaping (Int64) -> Void,
        openFolder: @escaping (Int32) -> Void,
        removeChat: @escaping (Int64) -> Void,
        removeFolder: @escaping (Int32) -> Void
    ) {
        self.context = context
        self.toggleBiometric = toggleBiometric
        self.openAutolock = openAutolock
        self.addPassword = addPassword
        self.openChat = openChat
        self.openFolder = openFolder
        self.removeChat = removeChat
        self.removeFolder = removeFolder
    }
}

private enum LitegramChatsSection: Int32 {
    case header
    case biometric
    case settings
    case chats
    case folders
}

private enum LitegramChatsEntryId: Hashable {
    case animationHeader
    case biometric
    case biometricFooter
    case autolock
    case addButton
    case settingsFooter
    case chatsHeader
    case chat(Int64)
    case foldersHeader
    case folder(Int32)
}

private enum LitegramChatsEntry: ItemListNodeEntry {
    case animationHeader(PresentationTheme, String, String)
    case biometric(PresentationTheme, String, Bool)
    case biometricFooter(PresentationTheme, String)
    case autolock(PresentationTheme, String, String)
    case addButton(PresentationTheme, String)
    case settingsFooter(PresentationTheme, String)
    case chatsHeader(PresentationTheme, String)
    case chat(index: Int, theme: PresentationTheme, peerId: Int64, name: String)
    case foldersHeader(PresentationTheme, String)
    case folder(index: Int, theme: PresentationTheme, filterId: Int32, name: String)

    var section: ItemListSectionId {
        switch self {
        case .animationHeader:
            return LitegramChatsSection.header.rawValue
        case .biometric, .biometricFooter:
            return LitegramChatsSection.biometric.rawValue
        case .autolock, .addButton, .settingsFooter:
            return LitegramChatsSection.settings.rawValue
        case .chatsHeader, .chat:
            return LitegramChatsSection.chats.rawValue
        case .foldersHeader, .folder:
            return LitegramChatsSection.folders.rawValue
        }
    }

    var stableId: LitegramChatsEntryId {
        switch self {
        case .animationHeader: return .animationHeader
        case .biometric: return .biometric
        case .biometricFooter: return .biometricFooter
        case .autolock: return .autolock
        case .addButton: return .addButton
        case .settingsFooter: return .settingsFooter
        case .chatsHeader: return .chatsHeader
        case let .chat(_, _, peerId, _): return .chat(peerId)
        case .foldersHeader: return .foldersHeader
        case let .folder(_, _, filterId, _): return .folder(filterId)
        }
    }

    static func ==(lhs: LitegramChatsEntry, rhs: LitegramChatsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.animationHeader(lt, la, ls), .animationHeader(rt, ra, rs)):
            return lt === rt && la == ra && ls == rs
        case let (.biometric(lt, ls, lv), .biometric(rt, rs, rv)):
            return lt === rt && ls == rs && lv == rv
        case let (.biometricFooter(lt, ls), .biometricFooter(rt, rs)):
            return lt === rt && ls == rs
        case let (.autolock(lt, ls, lv), .autolock(rt, rs, rv)):
            return lt === rt && ls == rs && lv == rv
        case let (.addButton(lt, ls), .addButton(rt, rs)):
            return lt === rt && ls == rs
        case let (.settingsFooter(lt, ls), .settingsFooter(rt, rs)):
            return lt === rt && ls == rs
        case let (.chatsHeader(lt, ls), .chatsHeader(rt, rs)):
            return lt === rt && ls == rs
        case let (.chat(li, lt, lp, ln), .chat(ri, rt, rp, rn)):
            return li == ri && lt === rt && lp == rp && ln == rn
        case let (.foldersHeader(lt, ls), .foldersHeader(rt, rs)):
            return lt === rt && ls == rs
        case let (.folder(li, lt, lf, ln), .folder(ri, rt, rf, rn)):
            return li == ri && lt === rt && lf == rf && ln == rn
        default:
            return false
        }
    }

    static func <(lhs: LitegramChatsEntry, rhs: LitegramChatsEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    private var sortIndex: Int {
        switch self {
        case .animationHeader: return -1
        case .biometric: return 0
        case .biometricFooter: return 1
        case .autolock: return 2
        case .addButton: return 3
        case .settingsFooter: return 4
        case .chatsHeader: return 5
        case let .chat(index, _, _, _): return 100 + index
        case .foldersHeader: return 200
        case let .folder(index, _, _, _): return 300 + index
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! LitegramChatsArguments

        switch self {
        case let .animationHeader(theme, animationName, text):
            return LitegramAnimationHeaderItem(theme: theme, animationName: animationName, text: text, sectionId: self.section)

        case let .biometric(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleBiometric(value)
            })

        case let .biometricFooter(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)

        case let .autolock(_, title, value):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.openAutolock()
            })

        case let .addButton(_, title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addPassword()
            })

        case let .settingsFooter(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)

        case let .chatsHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)

        case let .chat(_, _, peerId, name):
            return ItemListDisclosureItem(presentationData: presentationData, title: name, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openChat(peerId)
            })

        case let .foldersHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)

        case let .folder(_, _, filterId, name):
            return ItemListDisclosureItem(presentationData: presentationData, title: name, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openFolder(filterId)
            })
        }
    }
}

// MARK: - Animation Header Item

private final class LitegramAnimationHeaderItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let animationName: String
    let text: String
    let sectionId: ItemListSectionId

    init(theme: PresentationTheme, animationName: String, text: String, sectionId: ItemListSectionId) {
        self.theme = theme
        self.animationName = animationName
        self.text = text
        self.sectionId = sectionId
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = LitegramAnimationHeaderItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            guard let nodeValue = node() as? LitegramAnimationHeaderItemNode else {
                assertionFailure()
                return
            }
            let makeLayout = nodeValue.asyncLayout()
            async {
                let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                Queue.mainQueue().async {
                    completion(layout, { _ in apply() })
                }
            }
        }
    }
}

private final class LitegramAnimationHeaderItemNode: ListViewItemNode {
    private let textNode: TextNode
    private var animationNode: AnimatedStickerNode
    private var item: LitegramAnimationHeaderItem?

    init() {
        self.textNode = TextNode()
        self.textNode.isUserInteractionEnabled = false
        self.textNode.contentMode = .left
        self.textNode.contentsScale = UIScreen.main.scale

        self.animationNode = DefaultAnimatedStickerNodeImpl()

        super.init(layerBacked: false)

        self.addSubnode(self.animationNode)
        self.addSubnode(self.textNode)
    }

    func asyncLayout() -> (_ item: LitegramAnimationHeaderItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        let makeTextLayout = TextNode.asyncLayout(self.textNode)

        return { item, params, neighbors in
            let iconSize: CGFloat = 100.0
            let topInset: CGFloat = iconSize + 8.0

            let sideInset: CGFloat = 32.0 + params.leftInset
            let font = Font.regular(15.0)

            let attributedText = NSAttributedString(string: item.text, attributes: [
                .font: font,
                .foregroundColor: item.theme.list.freeTextColor
            ])

            let (textLayout, textApply) = makeTextLayout(TextNodeLayoutArguments(
                attributedString: attributedText,
                backgroundColor: nil,
                maximumNumberOfLines: 0,
                truncationType: .end,
                constrainedSize: CGSize(width: params.width - sideInset * 2.0, height: .greatestFiniteMagnitude),
                alignment: .center,
                cutout: nil,
                insets: UIEdgeInsets()
            ))

            let contentHeight = topInset + textLayout.size.height + 16.0
            let contentSize = CGSize(width: params.width, height: contentHeight)
            let insets = itemListNeighborsGroupedInsets(neighbors, params)
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)

            return (layout, { [weak self] in
                guard let self = self else { return }

                if self.item == nil {
                    self.animationNode.autoplay = true
                    let pixelSize = Int(iconSize * UIScreen.main.scale)
                    self.animationNode.setup(source: AnimatedStickerNodeLocalFileSource(name: item.animationName), width: pixelSize, height: pixelSize, playbackMode: .loop, mode: .direct(cachePathPrefix: nil))
                    self.animationNode.visibility = true
                }
                self.item = item

                let iconFrame = CGRect(x: floor((layout.size.width - iconSize) / 2.0), y: -4.0, width: iconSize, height: iconSize)
                self.animationNode.frame = iconFrame
                self.animationNode.updateLayout(size: CGSize(width: iconSize, height: iconSize))

                let _ = textApply()
                self.textNode.frame = CGRect(
                    x: floor((layout.size.width - textLayout.size.width) / 2.0),
                    y: topInset,
                    width: textLayout.size.width,
                    height: textLayout.size.height
                )
            })
        }
    }

    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }

    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
}

private struct LitegramChatsState: Equatable {
    var biometricEnabled: Bool
    var autolockSeconds: Int
    var chats: [(peerId: Int64, name: String)]
    var folders: [(filterId: Int32, name: String)]

    static func ==(lhs: LitegramChatsState, rhs: LitegramChatsState) -> Bool {
        return lhs.biometricEnabled == rhs.biometricEnabled
            && lhs.autolockSeconds == rhs.autolockSeconds
            && lhs.chats.count == rhs.chats.count
            && lhs.folders.count == rhs.folders.count
            && lhs.chats.elementsEqual(rhs.chats, by: { $0.peerId == $1.peerId && $0.name == $1.name })
            && lhs.folders.elementsEqual(rhs.folders, by: { $0.filterId == $1.filterId && $0.name == $1.name })
    }
}

private func litegramChatsEntries(state: LitegramChatsState, presentationData: PresentationData, strings: LitegramStrings) -> [LitegramChatsEntry] {
    let theme = presentationData.theme
    var entries: [LitegramChatsEntry] = []

    entries.append(.animationHeader(theme, "Passcode", strings.chatsSubtitle))

    let bioType = detectBiometryType()
    let bioTitle = bioType == .faceID ? strings.unlockWithFaceID : strings.unlockWithTouchID
    entries.append(.biometric(theme, bioTitle, state.biometricEnabled))
    entries.append(.biometricFooter(theme, strings.biometricFooter))

    let autolockValue = strings.autolockTitle(for: state.autolockSeconds)
    entries.append(.autolock(theme, strings.autoLock, autolockValue))
    entries.append(.addButton(theme, strings.addPassword))
    entries.append(.settingsFooter(theme, strings.pinFooter))

    if !state.chats.isEmpty {
        entries.append(.chatsHeader(theme, strings.protectedChats.uppercased()))
        for (i, chat) in state.chats.enumerated() {
            entries.append(.chat(index: i, theme: theme, peerId: chat.peerId, name: chat.name))
        }
    }

    if !state.folders.isEmpty {
        entries.append(.foldersHeader(theme, strings.protectedFolders.uppercased()))
        for (i, folder) in state.folders.enumerated() {
            entries.append(.folder(index: i, theme: theme, filterId: folder.filterId, name: folder.name))
        }
    }

    return entries
}

private func detectBiometryType() -> LABiometryType {
    let ctx = LAContext()
    _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    return ctx.biometryType
}

public func litegramChatsController(context: AccountContext) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let litegramStrings = LitegramStrings(languageCode: presentationData.strings.primaryComponent.languageCode)
    let locks = LitegramChatLocks.shared

    let statePromise = ValuePromise<LitegramChatsState>(LitegramChatsState(
        biometricEnabled: locks.isBiometricEnabled,
        autolockSeconds: locks.autolockSeconds,
        chats: [],
        folders: []
    ), ignoreRepeated: true)
    let stateValue = Atomic<LitegramChatsState>(value: LitegramChatsState(
        biometricEnabled: locks.isBiometricEnabled,
        autolockSeconds: locks.autolockSeconds,
        chats: [],
        folders: []
    ))
    let updateState: ((inout LitegramChatsState) -> Void) -> Void = { f in
        statePromise.set(stateValue.modify { value in
            var value = value
            f(&value)
            return value
        })
    }

    let actionsDisposable = DisposableSet()

    func reloadData() {
        let chatIds = locks.lockedChatIds()
        let folderIds = locks.lockedFolderIds()

        let peerIds = chatIds.map { PeerId($0) }
        let peerSignals = peerIds.map { pid in context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: pid)) }
        let filterSignal = context.engine.peers.currentChatListFilters() |> take(1)

        let combined = combineLatest(combineLatest(peerSignals), filterSignal)
        actionsDisposable.add((combined |> deliverOnMainQueue).startStrict(next: { peers, filters in
            let chats: [(peerId: Int64, name: String)] = chatIds.enumerated().map { i, pid in
                let name = peers[i]?.displayTitle(strings: presentationData.strings, displayOrder: .firstLast) ?? litegramStrings.chatFallback
                return (peerId: pid, name: name)
            }

            let folders: [(filterId: Int32, name: String)] = folderIds.map { fid in
                let name = filters.compactMap { f -> String? in
                    if case let .filter(id, title, _, _) = f, id == fid { return title.text }
                    return nil
                }.first ?? litegramStrings.folderFallback(fid)
                return (filterId: fid, name: name)
            }

            updateState { state in
                state.chats = chats
                state.folders = folders
                state.biometricEnabled = locks.isBiometricEnabled
                state.autolockSeconds = locks.autolockSeconds
            }
        }))
    }

    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentInWindowImpl: ((UIViewController) -> Void)?

    func applyPinTheme(to pin: LitegramPinController) {
        pin.strings = litegramStrings
        let pc = presentationData.theme.passcode
        let cols = LitegramPinController.passcodeColors(
            wallpaper: presentationData.chatWallpaper,
            isDark: presentationData.theme.overallDarkAppearance,
            bubbleFallback: presentationData.theme.chat.message.outgoing.bubble.withoutWallpaper.fill.first,
            passcodeTop: pc.backgroundColors.topColor,
            passcodeBottom: pc.backgroundColors.bottomColor,
            passcodeButton: pc.buttonColor
        )
        pin.applyPasscodeTheme(top: cols.top, bottom: cols.bottom, button: cols.button, isDark: presentationData.theme.overallDarkAppearance)
    }

    func presentPinSet(completion: @escaping (String) -> Void) {
        let pin = LitegramPinController(mode: .set)
        applyPinTheme(to: pin)
        pin.onPinSet = { p in completion(p) }
        presentInWindowImpl?(pin)
    }

    func presentPinVerifyChat(_ peerId: Int64, then: @escaping () -> Void) {
        let pin = LitegramPinController(mode: .verify(peerId: peerId))
        applyPinTheme(to: pin)
        pin.onPinVerified = then
        presentInWindowImpl?(pin)
    }

    func presentPinVerifyFolder(_ filterId: Int32, then: @escaping () -> Void) {
        let pin = LitegramPinController(mode: .verifyFolder(filterId: filterId))
        applyPinTheme(to: pin)
        pin.onPinVerified = then
        presentInWindowImpl?(pin)
    }

    let arguments = LitegramChatsArguments(
        context: context,
        toggleBiometric: { value in
            if value {
                let ctx = LAContext()
                if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
                    ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: litegramStrings.enableBiometrics) { ok, _ in
                        DispatchQueue.main.async {
                            if ok {
                                locks.isBiometricEnabled = true
                                updateState { $0.biometricEnabled = true }
                            } else {
                                updateState { $0.biometricEnabled = false }
                            }
                        }
                    }
                } else {
                    updateState { $0.biometricEnabled = false }
                }
            } else {
                locks.isBiometricEnabled = false
                updateState { $0.biometricEnabled = false }
            }
        },
        openAutolock: {
            let sheet = ActionSheetController(presentationData: presentationData)
            var items: [ActionSheetItem] = []

            for opt in LitegramChatLocks.autolockOptions(strings: litegramStrings) {
                items.append(ActionSheetButtonItem(title: opt.title, color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    locks.autolockSeconds = opt.seconds
                    updateState { $0.autolockSeconds = opt.seconds }
                }))
            }

            items.append(ActionSheetButtonItem(title: litegramStrings.customTime, color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                let alert = UIAlertController(title: litegramStrings.customTime, message: litegramStrings.enterTimeMinutes, preferredStyle: .alert)
                alert.addTextField { $0.keyboardType = .numberPad; $0.placeholder = litegramStrings.minutes }
                alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
                alert.addAction(UIAlertAction(title: litegramStrings.ok, style: .default) { _ in
                    if let text = alert.textFields?.first?.text, let mins = Int(text), mins > 0 {
                        locks.autolockSeconds = mins * 60
                        updateState { $0.autolockSeconds = mins * 60 }
                    }
                })
                DispatchQueue.main.async {
                    UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true)
                }
            }))

            sheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(sheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
        },
        addPassword: {
            let sheet = ActionSheetController(presentationData: presentationData)
            sheet.setItemGroups([
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: litegramStrings.addToChat, color: .accent, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(
                            context: context,
                            filter: [],
                            hasContactSelector: false,
                            title: litegramStrings.selectChat
                        ))
                        controller.peerSelected = { [weak controller] (peer: EnginePeer, _: Int64?) in
                            controller?.dismiss(animated: true)
                            let pid = peer.id.toInt64()
                            if locks.isLocked(pid) {
                                let a = UIAlertController(title: litegramStrings.chatAlreadyProtected, message: nil, preferredStyle: .alert)
                                a.addAction(UIAlertAction(title: litegramStrings.ok, style: .default))
                                UIApplication.shared.windows.first?.rootViewController?.present(a, animated: true)
                                return
                            }
                            presentPinSet { pin in
                                locks.setLock(pid, pin: pin)
                                reloadData()
                            }
                        }
                        pushControllerImpl?(controller)
                    }),
                    ActionSheetButtonItem(title: litegramStrings.addToFolder, color: .accent, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        let _ = (context.engine.peers.currentChatListFilters()
                        |> take(1)
                        |> deliverOnMainQueue).startStandalone(next: { filters in
                            let userFilters = filters.compactMap { f -> (Int32, String)? in
                                if case let .filter(id, title, _, _) = f { return (id, title.text) }
                                return nil
                            }
                            if userFilters.isEmpty {
                                let a = UIAlertController(title: litegramStrings.noFolders, message: litegramStrings.createFolder, preferredStyle: .alert)
                                a.addAction(UIAlertAction(title: litegramStrings.ok, style: .default))
                                UIApplication.shared.windows.first?.rootViewController?.present(a, animated: true)
                                return
                            }

                            let folderSheet = ActionSheetController(presentationData: presentationData)
                            var folderItems: [ActionSheetItem] = []
                            for (fid, title) in userFilters {
                                folderItems.append(ActionSheetButtonItem(title: title, color: .accent, action: { [weak folderSheet] in
                                    folderSheet?.dismissAnimated()
                                    if locks.isFolderLocked(fid) {
                                        let a = UIAlertController(title: litegramStrings.folderAlreadyProtected, message: nil, preferredStyle: .alert)
                                        a.addAction(UIAlertAction(title: litegramStrings.ok, style: .default))
                                        UIApplication.shared.windows.first?.rootViewController?.present(a, animated: true)
                                        return
                                    }
                                    presentPinSet { pin in
                                        locks.setFolderLock(fid, pin: pin)
                                        reloadData()
                                    }
                                }))
                            }
                            folderSheet.setItemGroups([
                                ActionSheetItemGroup(items: folderItems),
                                ActionSheetItemGroup(items: [
                                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak folderSheet] in
                                        folderSheet?.dismissAnimated()
                                    })
                                ])
                            ])
                            presentControllerImpl?(folderSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
                        })
                    })
                ]),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(sheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
        },
        openChat: { peerId in
            let sheet = ActionSheetController(presentationData: presentationData)
            sheet.setItemGroups([
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: litegramStrings.changePin, color: .accent, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        presentPinVerifyChat(peerId) {
                            presentPinSet { pin in
                                locks.setLock(peerId, pin: pin)
                            }
                        }
                    }),
                    ActionSheetButtonItem(title: litegramStrings.removeProtection, color: .destructive, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        presentPinVerifyChat(peerId) {
                            locks.removeLock(peerId)
                            reloadData()
                        }
                    })
                ]),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(sheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
        },
        openFolder: { filterId in
            let sheet = ActionSheetController(presentationData: presentationData)
            sheet.setItemGroups([
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: litegramStrings.changePin, color: .accent, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        presentPinVerifyFolder(filterId) {
                            presentPinSet { pin in
                                locks.setFolderLock(filterId, pin: pin)
                            }
                        }
                    }),
                    ActionSheetButtonItem(title: litegramStrings.removeProtection, color: .destructive, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        presentPinVerifyFolder(filterId) {
                            locks.removeFolderLock(filterId)
                            reloadData()
                        }
                    })
                ]),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(sheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
        },
        removeChat: { peerId in
            presentPinVerifyChat(peerId) {
                locks.removeLock(peerId)
                reloadData()
            }
        },
        removeFolder: { filterId in
            presentPinVerifyFolder(filterId) {
                locks.removeFolderLock(filterId)
                reloadData()
            }
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries = litegramChatsEntries(state: state, presentationData: presentationData, strings: litegramStrings)
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(litegramStrings.chatsTitle),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            animateChanges: false
        )
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        actionsDisposable.dispose()
    }

    let controller = ItemListController(context: context, state: signal)

    controller.didAppear = { _ in
        reloadData()
    }

    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    presentInWindowImpl = { [weak controller] vc in
        controller?.view.window?.rootViewController?.present(vc, animated: true)
    }

    reloadData()

    return controller
}
