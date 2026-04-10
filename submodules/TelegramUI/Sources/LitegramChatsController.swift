import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import Litegram
import LocalAuthentication

public final class LitegramChatsController: ViewController {
    private let context: AccountContext
    private var presentationData: PresentationData

    private var tableView: UITableView!

    private enum Section: Int, CaseIterable {
        case biometric
        case groups
        case folders
        case chats
    }

    private struct GroupRow {
        let id: Int
        let name: String
        let chatCount: Int
    }

    private struct FolderRow {
        let filterId: Int32
        let name: String
    }

    private struct ChatRow {
        let dialogId: Int64
        let name: String
    }

    private var groupRows: [GroupRow] = []
    private var folderRows: [FolderRow] = []
    private var chatRows: [ChatRow] = []

    private var peerNames: [Int64: String] = [:]
    private var peerDisposable: Disposable?

    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.title = "Чаты"
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped))
    }

    required public init(coder: NSCoder) {
        fatalError()
    }

    deinit {
        peerDisposable?.dispose()
    }

    override public func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "switchCell")
        tableView.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
        self.view.addSubview(tableView)

        reloadData()
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tableView.frame = view.bounds
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadData()
    }

    // MARK: - Data

    private func reloadData() {
        let locks = LitegramChatLocks.shared

        groupRows = locks.getAllGroupIds().compactMap { gid in
            guard let name = locks.getGroupName(gid) else { return nil }
            return GroupRow(id: gid, name: name, chatCount: locks.getGroupChats(gid).count)
        }

        folderRows = locks.getAllLockedFolderIds().map { fid in
            FolderRow(filterId: fid, name: "Папка \(fid)")
        }

        let standaloneIds = locks.getStandaloneLockedDialogIds()
        loadPeerNames(dialogIds: standaloneIds) { [weak self] in
            self?.chatRows = standaloneIds.map { did in
                ChatRow(dialogId: did, name: self?.peerNames[did] ?? "Чат \(did)")
            }
            self?.tableView?.reloadData()
        }

        tableView?.reloadData()
    }

    private func loadPeerNames(dialogIds: [Int64], completion: @escaping () -> Void) {
        guard !dialogIds.isEmpty else {
            completion()
            return
        }

        let peerIds = dialogIds.map { EnginePeer.Id(Int64($0)) }
        let signals = peerIds.map { peerId in
            self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        }

        peerDisposable = (combineLatest(signals)
        |> take(1)
        |> deliverOnMainQueue).startStrict(next: { [weak self] peers in
            for peer in peers {
                guard let peer = peer else { continue }
                if let self = self {
                    self.peerNames[peer.id._internalGetInt64Value()] = peer.displayTitle(strings: self.presentationData.strings, displayOrder: .firstLast)
                }
            }
            completion()
        })
    }

    // MARK: - Actions

    @objc private func addTapped() {
        let alert = UIAlertController(title: "Добавить защиту", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Защитить чат", style: .default) { [weak self] _ in
            self?.showChatPicker()
        })
        alert.addAction(UIAlertAction(title: "Создать группу чатов", style: .default) { [weak self] _ in
            self?.showCreateGroup()
        })
        alert.addAction(UIAlertAction(title: self.presentationData.strings.Common_Cancel, style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = self.navigationItem.rightBarButtonItem
        }
        present(alert, animated: true)
    }

    private func showChatPicker() {
        let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(
            context: context,
            filter: [.onlyPrivateChats, .includeNonMemberGroups, .includeBotChats],
            hasContactSelector: false,
            title: "Выберите чат"
        ))

        controller.peerSelected = { [weak self, weak controller] peer, _ in
            controller?.dismiss(animated: true)
            guard let self = self else { return }
            let dialogId = peer.id._internalGetInt64Value()

            if LitegramChatLocks.shared.isLocked(dialogId) {
                let alert = UIAlertController(title: "Чат уже защищён", message: nil, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
                return
            }

            let pinVC = LitegramPinController(mode: .set, onPinSet: { [weak self] pin, hint in
                LitegramChatLocks.shared.setLock(dialogId, pin: pin)
                if let hint = hint {
                    LitegramChatLocks.shared.setHint(dialogId, hint: hint)
                }
                self?.offerBiometric()
                self?.reloadData()
            })
            self.present(pinVC, animated: true)
        }

        push(controller)
    }

    private func showCreateGroup() {
        let nameAlert = UIAlertController(title: "Новая группа", message: "Введите название группы", preferredStyle: .alert)
        nameAlert.addTextField { $0.placeholder = "Название" }
        nameAlert.addAction(UIAlertAction(title: self.presentationData.strings.Common_Cancel, style: .cancel))
        nameAlert.addAction(UIAlertAction(title: "Далее", style: .default) { [weak self] _ in
            guard let self = self,
                  let name = nameAlert.textFields?.first?.text, !name.isEmpty else { return }
            self.showGroupChatPicker(groupName: name)
        })
        present(nameAlert, animated: true)
    }

    private func showGroupChatPicker(groupName: String) {
        let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(
            context: context,
            filter: [.onlyPrivateChats, .includeNonMemberGroups, .includeBotChats],
            hasContactSelector: false,
            title: "Выберите чаты"
        ))

        controller.peerSelected = { [weak self, weak controller] peer, _ in
            controller?.dismiss(animated: true)
            guard let self = self else { return }
            let dialogId = peer.id._internalGetInt64Value()

            let pinVC = LitegramPinController(mode: .set, onPinSet: { [weak self] pin, hint in
                let gid = LitegramChatLocks.shared.createGroup(name: groupName, pin: pin, chatIds: [dialogId])
                if let hint = hint {
                    LitegramChatLocks.shared.setGroupHint(gid, hint: hint)
                }
                self?.offerBiometric()
                self?.reloadData()
            })
            self.present(pinVC, animated: true)
        }

        push(controller)
    }

    private func offerBiometric() {
        guard !LitegramChatLocks.shared.isBiometricEnabled else { return }
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return }

        let alert = UIAlertController(
            title: "Биометрия",
            message: "Использовать биометрию для разблокировки чатов?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Да", style: .default) { _ in
            LitegramChatLocks.shared.isBiometricEnabled = true
        })
        alert.addAction(UIAlertAction(title: "Нет", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Group / Chat / Folder Settings

    private func showGroupSettings(_ group: GroupRow) {
        let entityId = LitegramChatLocks.shared.groupSettingsId(group.id)
        let needsPin = !LitegramChatLocks.shared.isSettingsUnlockedNow(entityId)

        let showSheet: () -> Void = { [weak self] in
            guard let self = self else { return }
            LitegramChatLocks.shared.markSettingsUnlocked(entityId)
            self.presentGroupSheet(group)
        }

        if needsPin {
            let pinVC = LitegramPinController(mode: .verifyGroup(groupId: group.id), onPinVerified: {
                showSheet()
            })
            present(pinVC, animated: true)
        } else {
            showSheet()
        }
    }

    private func presentGroupSheet(_ group: GroupRow) {
        let locks = LitegramChatLocks.shared
        let sheet = UIAlertController(title: group.name, message: "\(group.chatCount) чатов", preferredStyle: .actionSheet)

        let currentTimer = locks.getGroupTimer(group.id)
        sheet.addAction(UIAlertAction(title: "Таймер: \(timerString(currentTimer >= 0 ? currentTimer : 300))", style: .default) { [weak self] _ in
            self?.showTimerPicker { seconds in
                locks.setGroupTimer(group.id, seconds: seconds)
                self?.reloadData()
            }
        })

        let hideVal = locks.getGroupHide(group.id)
        let hideLabel = hideVal == 1 ? "Скрытие сообщений: ВКЛ" : "Скрытие сообщений: ВЫКЛ"
        sheet.addAction(UIAlertAction(title: hideLabel, style: .default) { [weak self] _ in
            locks.setGroupHide(group.id, value: hideVal == 1 ? 0 : 1)
            self?.reloadData()
        })

        sheet.addAction(UIAlertAction(title: "Изменить PIN", style: .default) { [weak self] _ in
            let pinVC = LitegramPinController(mode: .set, onPinSet: { pin, hint in
                locks.setGroupPin(group.id, newPin: pin)
                if let hint = hint {
                    locks.setGroupHint(group.id, hint: hint)
                }
            })
            self?.present(pinVC, animated: true)
        })

        sheet.addAction(UIAlertAction(title: "Добавить чат", style: .default) { [weak self] _ in
            self?.addChatToExistingGroup(group.id)
        })

        sheet.addAction(UIAlertAction(title: "Удалить группу", style: .destructive) { [weak self] _ in
            let confirm = UIAlertController(title: "Удалить группу?", message: "Защита будет снята со всех чатов группы", preferredStyle: .alert)
            confirm.addAction(UIAlertAction(title: "Удалить", style: .destructive) { _ in
                locks.removeGroup(group.id)
                self?.reloadData()
            })
            confirm.addAction(UIAlertAction(title: self?.presentationData.strings.Common_Cancel ?? "Отмена", style: .cancel))
            self?.present(confirm, animated: true)
        })

        sheet.addAction(UIAlertAction(title: self.presentationData.strings.Common_Cancel, style: .cancel))
        present(sheet, animated: true)
    }

    private func addChatToExistingGroup(_ groupId: Int) {
        let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(
            context: context,
            filter: [.onlyPrivateChats, .includeNonMemberGroups, .includeBotChats],
            hasContactSelector: false,
            title: "Добавить чат"
        ))

        controller.peerSelected = { [weak self, weak controller] peer, _ in
            controller?.dismiss(animated: true)
            let dialogId = peer.id._internalGetInt64Value()
            LitegramChatLocks.shared.addChatToGroup(groupId, dialogId: dialogId)
            self?.reloadData()
        }
        push(controller)
    }

    private func showChatSettings(_ chat: ChatRow) {
        let locks = LitegramChatLocks.shared
        let needsPin = !locks.isSettingsUnlockedNow(chat.dialogId)

        let showSheet: () -> Void = { [weak self] in
            guard let self = self else { return }
            locks.markSettingsUnlocked(chat.dialogId)
            self.presentChatSheet(chat)
        }

        if needsPin {
            let pinVC = LitegramPinController(mode: .verify(dialogId: chat.dialogId), onPinVerified: {
                showSheet()
            })
            present(pinVC, animated: true)
        } else {
            showSheet()
        }
    }

    private func presentChatSheet(_ chat: ChatRow) {
        let locks = LitegramChatLocks.shared
        let sheet = UIAlertController(title: chat.name, message: nil, preferredStyle: .actionSheet)

        let currentTimer = locks.getChatAutolockSeconds(chat.dialogId)
        let effectiveTimer = locks.getEffectiveAutolockSeconds(chat.dialogId)
        sheet.addAction(UIAlertAction(title: "Таймер: \(timerString(currentTimer >= 0 ? currentTimer : effectiveTimer))", style: .default) { [weak self] _ in
            self?.showTimerPicker { seconds in
                locks.setChatAutolockSeconds(chat.dialogId, seconds: seconds)
                self?.reloadData()
            }
        })

        let hideVal = locks.getChatHidePreview(chat.dialogId)
        let hideLabel = hideVal == 1 ? "Скрытие сообщений: ВКЛ" : "Скрытие сообщений: ВЫКЛ"
        sheet.addAction(UIAlertAction(title: hideLabel, style: .default) { [weak self] _ in
            locks.setChatHidePreview(chat.dialogId, value: hideVal == 1 ? 0 : 1)
            self?.reloadData()
        })

        sheet.addAction(UIAlertAction(title: "Изменить PIN", style: .default) { [weak self] _ in
            let pinVC = LitegramPinController(mode: .set, onPinSet: { pin, hint in
                locks.setLock(chat.dialogId, pin: pin)
                if let hint = hint {
                    locks.setHint(chat.dialogId, hint: hint)
                }
            })
            self?.present(pinVC, animated: true)
        })

        sheet.addAction(UIAlertAction(title: "Снять защиту", style: .destructive) { [weak self] _ in
            locks.removeLock(chat.dialogId)
            self?.reloadData()
        })

        sheet.addAction(UIAlertAction(title: self.presentationData.strings.Common_Cancel, style: .cancel))
        present(sheet, animated: true)
    }

    private func showFolderSettings(_ folder: FolderRow) {
        let locks = LitegramChatLocks.shared
        let sheet = UIAlertController(title: folder.name, message: nil, preferredStyle: .actionSheet)

        sheet.addAction(UIAlertAction(title: "Изменить PIN", style: .default) { [weak self] _ in
            let pinVC = LitegramPinController(mode: .set, onPinSet: { pin, hint in
                locks.setFolderLock(folder.filterId, pin: pin)
                if let hint = hint {
                    locks.setFolderHint(folder.filterId, hint: hint)
                }
            })
            self?.present(pinVC, animated: true)
        })

        sheet.addAction(UIAlertAction(title: "Снять защиту", style: .destructive) { [weak self] _ in
            locks.removeFolderLock(folder.filterId)
            self?.reloadData()
        })

        sheet.addAction(UIAlertAction(title: self.presentationData.strings.Common_Cancel, style: .cancel))
        present(sheet, animated: true)
    }

    // MARK: - Timer Picker

    private func showTimerPicker(completion: @escaping (Int) -> Void) {
        let sheet = UIAlertController(title: "Таймер автоблокировки", message: nil, preferredStyle: .actionSheet)
        for value in LitegramChatLocks.timerValues {
            sheet.addAction(UIAlertAction(title: timerString(value), style: .default) { _ in
                completion(value)
            })
        }
        sheet.addAction(UIAlertAction(title: self.presentationData.strings.Common_Cancel, style: .cancel))
        present(sheet, animated: true)
    }

    private func timerString(_ seconds: Int) -> String {
        switch seconds {
        case 0: return "Всегда блокировать"
        case 30: return "30 секунд"
        case 60: return "1 минута"
        case 300: return "5 минут"
        case 900: return "15 минут"
        case 3600: return "1 час"
        default: return "\(seconds) сек."
        }
    }
}

// MARK: - UITableViewDataSource & Delegate

extension LitegramChatsController: UITableViewDataSource, UITableViewDelegate {

    public func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sec = Section(rawValue: section) else { return 0 }
        switch sec {
        case .biometric: return 1
        case .groups: return groupRows.count
        case .folders: return folderRows.count
        case .chats: return chatRows.count
        }
    }

    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sec = Section(rawValue: section) else { return nil }
        switch sec {
        case .biometric: return nil
        case .groups: return groupRows.isEmpty ? nil : "Группы чатов"
        case .folders: return folderRows.isEmpty ? nil : "Защищённые папки"
        case .chats: return chatRows.isEmpty ? nil : "Защищённые чаты"
        }
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let sec = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch sec {
        case .biometric:
            let cell = tableView.dequeueReusableCell(withIdentifier: "switchCell", for: indexPath)
            cell.textLabel?.text = "Биометрия"
            cell.selectionStyle = .none
            let toggle = UISwitch()
            toggle.isOn = LitegramChatLocks.shared.isBiometricEnabled
            toggle.addTarget(self, action: #selector(biometricToggled(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            cell.imageView?.image = UIImage(systemName: "faceid")
            cell.imageView?.tintColor = self.presentationData.theme.list.itemAccentColor
            applyTheme(to: cell)
            return cell

        case .groups:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            let group = groupRows[indexPath.row]
            cell.textLabel?.text = "📁 \(group.name) (\(group.chatCount) чатов)"
            cell.accessoryType = .disclosureIndicator
            applyTheme(to: cell)
            return cell

        case .folders:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            let folder = folderRows[indexPath.row]
            cell.textLabel?.text = "🔒 \(folder.name)"
            cell.accessoryType = .disclosureIndicator
            applyTheme(to: cell)
            return cell

        case .chats:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            let chat = chatRows[indexPath.row]
            cell.textLabel?.text = "🔒 \(chat.name)"
            cell.accessoryType = .disclosureIndicator
            applyTheme(to: cell)
            return cell
        }
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let sec = Section(rawValue: indexPath.section) else { return }

        switch sec {
        case .biometric:
            break
        case .groups:
            showGroupSettings(groupRows[indexPath.row])
        case .folders:
            showFolderSettings(folderRows[indexPath.row])
        case .chats:
            showChatSettings(chatRows[indexPath.row])
        }
    }

    public func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard let sec = Section(rawValue: indexPath.section) else { return false }
        return sec != .biometric
    }

    public func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, let sec = Section(rawValue: indexPath.section) else { return }
        let locks = LitegramChatLocks.shared

        switch sec {
        case .groups:
            let group = groupRows[indexPath.row]
            locks.removeGroup(group.id)
        case .folders:
            let folder = folderRows[indexPath.row]
            locks.removeFolderLock(folder.filterId)
        case .chats:
            let chat = chatRows[indexPath.row]
            locks.removeLock(chat.dialogId)
        default:
            return
        }
        reloadData()
    }

    private func applyTheme(to cell: UITableViewCell) {
        let theme = self.presentationData.theme
        cell.backgroundColor = theme.list.itemBlocksBackgroundColor
        cell.textLabel?.textColor = theme.list.itemPrimaryTextColor
    }

    @objc private func biometricToggled(_ sender: UISwitch) {
        if sender.isOn {
            let context: LAContext = LAContext()
            var error: NSError?
            if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
                context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Включить биометрию для Litegram") { success, _ in
                    DispatchQueue.main.async {
                        if success {
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
}
