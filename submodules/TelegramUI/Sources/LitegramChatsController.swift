import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import LocalizedPeerData
import Litegram
import LocalAuthentication

public final class LitegramChatsController: ViewController, UITableViewDataSource, UITableViewDelegate {

    private let context: AccountContext
    private var presentationData: PresentationData
    private var tableView: UITableView?
    private var peerDisposable: Disposable?

    private struct LockedChat {
        let peerId: Int64
        var name: String
    }
    private struct LockedFolder {
        let filterId: Int32
        var name: String
    }

    private var lockedChats: [LockedChat] = []
    private var lockedFolders: [LockedFolder] = []

    private enum Sec: Int, CaseIterable {
        case biometric = 0
        case autolock
        case addButton
        case chats
        case folders
    }

    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.title = "Чаты"
    }

    required init(coder: NSCoder) { fatalError() }

    deinit {
        peerDisposable?.dispose()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.dataSource = self
        tv.delegate = self
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        tv.backgroundColor = presentationData.theme.list.blocksBackgroundColor
        tv.separatorColor = presentationData.theme.list.itemBlocksSeparatorColor
        self.view.addSubview(tv)
        self.tableView = tv
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let navH = (self.navigationBar?.frame.maxY ?? 0)
        tableView?.frame = CGRect(x: 0, y: navH, width: layout.size.width, height: layout.size.height - navH)
    }

    // MARK: - Data

    private func reload() {
        let locks = LitegramChatLocks.shared
        let chatIds = locks.lockedChatIds()
        let folderIds = locks.lockedFolderIds()

        lockedFolders = []
        let _ = (context.engine.peers.currentChatListFilters()
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { [weak self] filters in
            guard let self = self else { return }
            for fid in folderIds {
                let name = filters.compactMap { f -> String? in
                    if case let .filter(id, title, _, _) = f, id == fid { return title.text }
                    return nil
                }.first ?? "Папка \(fid)"
                self.lockedFolders.append(LockedFolder(filterId: fid, name: name))
            }
            self.tableView?.reloadData()
        })

        peerDisposable?.dispose()
        if chatIds.isEmpty {
            lockedChats = []
            tableView?.reloadData()
            return
        }

        let peerIds = chatIds.map { PeerId($0) }
        let signals = peerIds.map { pid in context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: pid)) }

        peerDisposable = (combineLatest(signals)
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { [weak self] peers in
            guard let self = self else { return }
            self.lockedChats = []
            for (i, peer) in peers.enumerated() {
                let pid = chatIds[i]
                let name = peer?.displayTitle(strings: self.presentationData.strings, displayOrder: .firstLast) ?? "Чат"
                self.lockedChats.append(LockedChat(peerId: pid, name: name))
            }
            self.tableView?.reloadData()
        })
    }

    // MARK: - TableView

    public func numberOfSections(in tableView: UITableView) -> Int {
        return Sec.allCases.count
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let s = Sec(rawValue: section) else { return 0 }
        switch s {
        case .biometric: return 1
        case .autolock: return 1
        case .addButton: return 1
        case .chats: return lockedChats.count
        case .folders: return lockedFolders.count
        }
    }

    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let s = Sec(rawValue: section) else { return nil }
        if s == .chats && !lockedChats.isEmpty { return "Защищённые чаты" }
        if s == .folders && !lockedFolders.isEmpty { return "Защищённые папки" }
        return nil
    }

    public func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == Sec.biometric.rawValue {
            return "Используйте биометрию для быстрой разблокировки защищённых чатов."
        }
        if section == Sec.addButton.rawValue && lockedChats.isEmpty && lockedFolders.isEmpty {
            return "Установите PIN-код на чат или папку. При открытии защищённого чата потребуется ввод PIN."
        }
        return nil
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "c", for: indexPath)
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.imageView?.image = nil
        cell.selectionStyle = .default
        cell.textLabel?.textAlignment = .natural
        cell.textLabel?.font = .systemFont(ofSize: 17)

        let theme = presentationData.theme
        cell.backgroundColor = theme.list.itemBlocksBackgroundColor
        cell.textLabel?.textColor = theme.list.itemPrimaryTextColor

        guard let s = Sec(rawValue: indexPath.section) else { return cell }

        switch s {
        case .biometric:
            let bioType = detectBioType()
            cell.textLabel?.text = bioType == .faceID ? "Разблокировка по Face ID" : "Разблокировка по Touch ID"
            cell.selectionStyle = .none
            let toggle = UISwitch()
            toggle.isOn = LitegramChatLocks.shared.isBiometricEnabled
            toggle.onTintColor = theme.list.itemAccentColor
            toggle.addTarget(self, action: #selector(bioToggled(_:)), for: .valueChanged)
            cell.accessoryView = toggle

        case .autolock:
            cell.textLabel?.text = "Автоблокировка"
            cell.accessoryType = .disclosureIndicator
            let detail = UILabel()
            detail.text = LitegramChatLocks.shared.autolockTitle()
            detail.textColor = theme.list.itemSecondaryTextColor
            detail.font = .systemFont(ofSize: 17)
            detail.sizeToFit()
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
            cell.detailTextLabel?.text = nil
            let stack = UIStackView(arrangedSubviews: [detail])
            stack.frame = CGRect(x: 0, y: 0, width: detail.frame.width + 8, height: 22)
            cell.accessoryView = stack

        case .addButton:
            cell.textLabel?.text = "Добавить пароль"
            cell.textLabel?.textColor = theme.list.itemAccentColor
            cell.imageView?.image = UIImage(systemName: "plus.circle.fill")
            cell.imageView?.tintColor = theme.list.itemAccentColor

        case .chats:
            let chat = lockedChats[indexPath.row]
            cell.textLabel?.text = chat.name
            cell.imageView?.image = UIImage(systemName: "lock.fill")
            cell.imageView?.tintColor = theme.list.itemSecondaryTextColor

        case .folders:
            let folder = lockedFolders[indexPath.row]
            cell.textLabel?.text = folder.name
            cell.imageView?.image = UIImage(systemName: "folder.fill")
            cell.imageView?.tintColor = theme.list.itemSecondaryTextColor
        }

        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let s = Sec(rawValue: indexPath.section) else { return }

        switch s {
        case .autolock:
            showAutolockPicker()
        case .addButton:
            showAddMenu()
        case .chats:
            let chat = lockedChats[indexPath.row]
            showChatOptions(chat)
        case .folders:
            let folder = lockedFolders[indexPath.row]
            showFolderOptions(folder)
        default:
            break
        }
    }

    public func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard let s = Sec(rawValue: indexPath.section) else { return false }
        return s == .chats || s == .folders
    }

    public func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let s = Sec(rawValue: indexPath.section) else { return nil }

        let unlockAction = UIContextualAction(style: .destructive, title: "Разблок.") { [weak self] _, _, done in
            guard let self = self else { done(false); return }

            if s == .chats {
                let chat = self.lockedChats[indexPath.row]
                self.verifyAndRemoveChatLock(chat.peerId)
            } else if s == .folders {
                let folder = self.lockedFolders[indexPath.row]
                self.verifyAndRemoveFolderLock(folder.filterId)
            }
            done(true)
        }
        unlockAction.backgroundColor = .systemRed

        return UISwipeActionsConfiguration(actions: [unlockAction])
    }

    // MARK: - Biometric

    private func detectBioType() -> LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }

    @objc private func bioToggled(_ sender: UISwitch) {
        if sender.isOn {
            let ctx = LAContext()
            if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
                ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Включить биометрию для защиты чатов") { ok, _ in
                    DispatchQueue.main.async {
                        if ok {
                            LitegramChatLocks.shared.isBiometricEnabled = true
                        } else {
                            sender.setOn(false, animated: true)
                        }
                    }
                }
            } else {
                sender.setOn(false, animated: true)
            }
        } else {
            LitegramChatLocks.shared.isBiometricEnabled = false
        }
    }

    // MARK: - Autolock

    private func showAutolockPicker() {
        let sheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []

        for opt in LitegramChatLocks.autolockOptions {
            items.append(ActionSheetButtonItem(title: opt.title, color: .accent, action: { [weak sheet, weak self] in
                sheet?.dismissAnimated()
                LitegramChatLocks.shared.autolockSeconds = opt.seconds
                self?.tableView?.reloadData()
            }))
        }

        items.append(ActionSheetButtonItem(title: "Своё время", color: .accent, action: { [weak sheet, weak self] in
            sheet?.dismissAnimated()
            self?.showCustomTimer()
        }))

        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })
            ])
        ])
        present(sheet, in: .window(.root))
    }

    private func showCustomTimer() {
        let alert = UIAlertController(title: "Своё время", message: "Введите время в минутах", preferredStyle: .alert)
        alert.addTextField { $0.keyboardType = .numberPad; $0.placeholder = "Минуты" }
        alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            if let text = alert.textFields?.first?.text, let mins = Int(text), mins > 0 {
                LitegramChatLocks.shared.autolockSeconds = mins * 60
                self?.tableView?.reloadData()
            }
        })
        self.view.window?.rootViewController?.present(alert, animated: true)
    }

    // MARK: - Add

    private func showAddMenu() {
        let sheet = ActionSheetController(presentationData: presentationData)
        sheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: "🔒 На чат", color: .accent, action: { [weak sheet, weak self] in
                    sheet?.dismissAnimated()
                    self?.pickChat()
                }),
                ActionSheetButtonItem(title: "📁 На папку", color: .accent, action: { [weak sheet, weak self] in
                    sheet?.dismissAnimated()
                    self?.pickFolder()
                })
            ]),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })
            ])
        ])
        present(sheet, in: .window(.root))
    }

    private func pickChat() {
        let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(
            context: context,
            filter: [],
            hasContactSelector: false,
            title: "Выберите чат"
        ))

        controller.peerSelected = { [weak self, weak controller] (peer: EnginePeer, _: Int64?) in
            controller?.dismiss(animated: true)
            guard let self = self else { return }
            let pid = peer.id.toInt64()

            if LitegramChatLocks.shared.isLocked(pid) {
                let a = UIAlertController(title: "Чат уже защищён", message: nil, preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "OK", style: .default))
                self.view.window?.rootViewController?.present(a, animated: true)
                return
            }

            self.presentPinSet { pin in
                LitegramChatLocks.shared.setLock(pid, pin: pin)
                self.reload()
            }
        }
        push(controller)
    }

    private func pickFolder() {
        let _ = (context.engine.peers.currentChatListFilters()
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { [weak self] filters in
            guard let self = self else { return }
            let userFilters = filters.compactMap { f -> (Int32, String)? in
                if case let .filter(id, title, _, _) = f { return (id, title.text) }
                return nil
            }
            if userFilters.isEmpty {
                let a = UIAlertController(title: "Нет папок", message: "Создайте папку чатов в настройках Telegram", preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "OK", style: .default))
                self.view.window?.rootViewController?.present(a, animated: true)
                return
            }

            let sheet = ActionSheetController(presentationData: self.presentationData)
            var items: [ActionSheetItem] = []
            for (fid, title) in userFilters {
                items.append(ActionSheetButtonItem(title: title, color: .accent, action: { [weak sheet, weak self] in
                    sheet?.dismissAnimated()
                    guard let self = self else { return }
                    if LitegramChatLocks.shared.isFolderLocked(fid) {
                        let a = UIAlertController(title: "Папка уже защищена", message: nil, preferredStyle: .alert)
                        a.addAction(UIAlertAction(title: "OK", style: .default))
                        self.view.window?.rootViewController?.present(a, animated: true)
                        return
                    }
                    self.presentPinSet { pin in
                        LitegramChatLocks.shared.setFolderLock(fid, pin: pin)
                        self.reload()
                    }
                }))
            }
            sheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: self.presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            self.present(sheet, in: .window(.root))
        })
    }

    // MARK: - PIN Presentation

    private func presentPinSet(completion: @escaping (String) -> Void) {
        let pin = LitegramPinController(mode: .set)
        pin.applyAccentColor(presentationData.theme.list.itemAccentColor)
        pin.onPinSet = { p in completion(p) }
        self.view.window?.rootViewController?.present(pin, animated: true)
    }

    private func presentPinVerifyChat(_ peerId: Int64, then: @escaping () -> Void) {
        let pin = LitegramPinController(mode: .verify(peerId: peerId))
        pin.applyAccentColor(presentationData.theme.list.itemAccentColor)
        pin.onPinVerified = then
        self.view.window?.rootViewController?.present(pin, animated: true)
    }

    private func presentPinVerifyFolder(_ filterId: Int32, then: @escaping () -> Void) {
        let pin = LitegramPinController(mode: .verifyFolder(filterId: filterId))
        pin.applyAccentColor(presentationData.theme.list.itemAccentColor)
        pin.onPinVerified = then
        self.view.window?.rootViewController?.present(pin, animated: true)
    }

    // MARK: - Remove Lock

    private func verifyAndRemoveChatLock(_ peerId: Int64) {
        presentPinVerifyChat(peerId) { [weak self] in
            LitegramChatLocks.shared.removeLock(peerId)
            self?.reload()
        }
    }

    private func verifyAndRemoveFolderLock(_ filterId: Int32) {
        presentPinVerifyFolder(filterId) { [weak self] in
            LitegramChatLocks.shared.removeFolderLock(filterId)
            self?.reload()
        }
    }

    // MARK: - Options

    private func showChatOptions(_ chat: LockedChat) {
        let sheet = ActionSheetController(presentationData: presentationData)
        sheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: "🔑 Изменить PIN", color: .accent, action: { [weak sheet, weak self] in
                    sheet?.dismissAnimated()
                    guard let self = self else { return }
                    self.presentPinVerifyChat(chat.peerId) {
                        self.presentPinSet { pin in
                            LitegramChatLocks.shared.setLock(chat.peerId, pin: pin)
                        }
                    }
                }),
                ActionSheetButtonItem(title: "🗑 Снять защиту", color: .destructive, action: { [weak sheet, weak self] in
                    sheet?.dismissAnimated()
                    self?.verifyAndRemoveChatLock(chat.peerId)
                })
            ]),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })
            ])
        ])
        present(sheet, in: .window(.root))
    }

    private func showFolderOptions(_ folder: LockedFolder) {
        let sheet = ActionSheetController(presentationData: presentationData)
        sheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: "🔑 Изменить PIN", color: .accent, action: { [weak sheet, weak self] in
                    sheet?.dismissAnimated()
                    guard let self = self else { return }
                    self.presentPinVerifyFolder(folder.filterId) {
                        self.presentPinSet { pin in
                            LitegramChatLocks.shared.setFolderLock(folder.filterId, pin: pin)
                        }
                    }
                }),
                ActionSheetButtonItem(title: "🗑 Снять защиту", color: .destructive, action: { [weak sheet, weak self] in
                    sheet?.dismissAnimated()
                    self?.verifyAndRemoveFolderLock(folder.filterId)
                })
            ]),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })
            ])
        ])
        present(sheet, in: .window(.root))
    }
}
