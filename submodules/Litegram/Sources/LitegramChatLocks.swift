import Foundation
import CryptoKit

public final class LitegramChatLocks {
    public static let shared = LitegramChatLocks()

    private let defaults: UserDefaults
    private var lastUnlockTime: [Int64: TimeInterval] = [:]
    private var lastSettingsUnlockTime: [Int64: TimeInterval] = [:]
    private let lock = NSLock()

    public static let timerValues: [Int] = [0, 30, 60, 300, 900, 3600]
    private static let settingsUnlockDuration: TimeInterval = 30.0
    private static let folderIdOffset: Int64 = 0x7F00000000
    private static let groupIdOffset: Int64 = 0x7E00000000

    private init() {
        self.defaults = UserDefaults(suiteName: "litegram_chat_locks") ?? .standard
    }

    // MARK: - Salt & Hashing

    private func getSalt() -> String {
        if let salt = defaults.string(forKey: "pin_salt") {
            return salt
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let salt = bytes.map { String(format: "%02x", $0) }.joined()
        defaults.set(salt, forKey: "pin_salt")
        return salt
    }

    private func hashPin(_ pin: String) -> String {
        let input = getSalt() + pin
        let hash = SHA256.hash(data: Data(input.utf8))
        return "v2:" + hash.map { String(format: "%02x", $0) }.joined()
    }

    private func sha256Simple(_ input: String) -> String {
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func verifyAndUpgrade(storedHash: String, pin: String, prefKey: String) -> Bool {
        if storedHash.hasPrefix("v2:") {
            return storedHash == hashPin(pin)
        }
        if storedHash == sha256Simple(pin) {
            defaults.set(hashPin(pin), forKey: prefKey)
            return true
        }
        return false
    }

    // MARK: - Chat Locks

    public func isLocked(_ dialogId: Int64) -> Bool {
        return defaults.string(forKey: "lock_\(dialogId)") != nil
    }

    public func setLock(_ dialogId: Int64, pin: String) {
        defaults.set(hashPin(pin), forKey: "lock_\(dialogId)")
    }

    public func setLockHash(_ dialogId: Int64, hash: String) {
        defaults.set(hash, forKey: "lock_\(dialogId)")
    }

    public func removeLock(_ dialogId: Int64) {
        defaults.removeObject(forKey: "lock_\(dialogId)")
        defaults.removeObject(forKey: "hint_\(dialogId)")
        defaults.removeObject(forKey: "timer_\(dialogId)")
        defaults.removeObject(forKey: "hide_\(dialogId)")
        lock.lock()
        lastUnlockTime.removeValue(forKey: dialogId)
        lock.unlock()
    }

    public func checkPin(_ dialogId: Int64, pin: String) -> Bool {
        guard let stored = defaults.string(forKey: "lock_\(dialogId)") else { return false }
        return verifyAndUpgrade(storedHash: stored, pin: pin, prefKey: "lock_\(dialogId)")
    }

    public func getHint(_ dialogId: Int64) -> String? {
        return defaults.string(forKey: "hint_\(dialogId)")
    }

    public func setHint(_ dialogId: Int64, hint: String?) {
        if let h = hint, !h.isEmpty {
            defaults.set(h, forKey: "hint_\(dialogId)")
        } else {
            defaults.removeObject(forKey: "hint_\(dialogId)")
        }
    }

    public func getAllLockedDialogIds() -> [Int64] {
        let keys = defaults.dictionaryRepresentation().keys
        return keys.compactMap { key -> Int64? in
            guard key.hasPrefix("lock_") else { return nil }
            return Int64(key.dropFirst(5))
        }
    }

    public func getStandaloneLockedDialogIds() -> [Int64] {
        let allLocked = getAllLockedDialogIds()
        let allGroupIds = getAllGroupIds()
        let groupedChats = Set(allGroupIds.flatMap { getGroupChats($0) })
        return allLocked.filter { !groupedChats.contains($0) }
    }

    // MARK: - Unlock State

    public func isUnlockedNow(_ dialogId: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let timestamp = lastUnlockTime[dialogId] else { return false }
        let seconds = getEffectiveAutolockSeconds(dialogId)
        if seconds == 0 { return false }
        return Date().timeIntervalSince1970 - timestamp < Double(seconds)
    }

    public func markUnlocked(_ dialogId: Int64) {
        lock.lock()
        lastUnlockTime[dialogId] = Date().timeIntervalSince1970
        lock.unlock()
    }

    public func relockAll() {
        lock.lock()
        lastUnlockTime.removeAll()
        lastSettingsUnlockTime.removeAll()
        lock.unlock()
    }

    // MARK: - Settings Grace Period

    public func isSettingsUnlockedNow(_ entityId: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let timestamp = lastSettingsUnlockTime[entityId] else { return false }
        return Date().timeIntervalSince1970 - timestamp < Self.settingsUnlockDuration
    }

    public func markSettingsUnlocked(_ entityId: Int64) {
        lock.lock()
        lastSettingsUnlockTime[entityId] = Date().timeIntervalSince1970
        lock.unlock()
    }

    // MARK: - Autolock Timer

    public func getChatAutolockSeconds(_ dialogId: Int64) -> Int {
        let val = defaults.object(forKey: "timer_\(dialogId)") as? Int
        return val ?? -1
    }

    public func setChatAutolockSeconds(_ dialogId: Int64, seconds: Int) {
        defaults.set(seconds, forKey: "timer_\(dialogId)")
    }

    public func getEffectiveAutolockSeconds(_ dialogId: Int64) -> Int {
        let perChat = getChatAutolockSeconds(dialogId)
        if perChat >= 0 { return perChat }
        let groupId = findGroupForChat(dialogId)
        if groupId >= 0 {
            let groupTimer = getGroupTimer(groupId)
            if groupTimer >= 0 { return groupTimer }
        }
        return 300
    }

    // MARK: - Hide Preview

    public func getChatHidePreview(_ dialogId: Int64) -> Int {
        let val = defaults.object(forKey: "hide_\(dialogId)") as? Int
        return val ?? -1
    }

    public func setChatHidePreview(_ dialogId: Int64, value: Int) {
        defaults.set(value, forKey: "hide_\(dialogId)")
    }

    public func isEffectiveHidePreview(_ dialogId: Int64) -> Bool {
        let perChat = getChatHidePreview(dialogId)
        if perChat >= 0 { return perChat == 1 }
        let groupId = findGroupForChat(dialogId)
        if groupId >= 0 {
            let groupHide = getGroupHide(groupId)
            if groupHide >= 0 { return groupHide == 1 }
        }
        return false
    }

    // MARK: - Folder Locks

    public func folderDialogId(_ filterId: Int32) -> Int64 {
        return Self.folderIdOffset + Int64(filterId)
    }

    public func isFolderLocked(_ filterId: Int32) -> Bool {
        return defaults.string(forKey: "flk_\(filterId)") != nil
    }

    public func setFolderLock(_ filterId: Int32, pin: String) {
        defaults.set(hashPin(pin), forKey: "flk_\(filterId)")
    }

    public func removeFolderLock(_ filterId: Int32) {
        defaults.removeObject(forKey: "flk_\(filterId)")
        defaults.removeObject(forKey: "fhint_\(filterId)")
        defaults.removeObject(forKey: "fltimer_\(filterId)")
        let fid = folderDialogId(filterId)
        lock.lock()
        lastUnlockTime.removeValue(forKey: fid)
        lock.unlock()
    }

    public func checkFolderPin(_ filterId: Int32, pin: String) -> Bool {
        guard let stored = defaults.string(forKey: "flk_\(filterId)") else { return false }
        return verifyAndUpgrade(storedHash: stored, pin: pin, prefKey: "flk_\(filterId)")
    }

    public func isFolderUnlockedNow(_ filterId: Int32) -> Bool {
        let fid = folderDialogId(filterId)
        lock.lock()
        defer { lock.unlock() }
        guard let timestamp = lastUnlockTime[fid] else { return false }
        let seconds = getEffectiveFolderAutolockSeconds(filterId)
        if seconds == 0 { return false }
        return Date().timeIntervalSince1970 - timestamp < Double(seconds)
    }

    public func markFolderUnlocked(_ filterId: Int32) {
        let fid = folderDialogId(filterId)
        lock.lock()
        lastUnlockTime[fid] = Date().timeIntervalSince1970
        lock.unlock()
    }

    public func getFolderHint(_ filterId: Int32) -> String? {
        return defaults.string(forKey: "fhint_\(filterId)")
    }

    public func setFolderHint(_ filterId: Int32, hint: String?) {
        if let h = hint, !h.isEmpty {
            defaults.set(h, forKey: "fhint_\(filterId)")
        } else {
            defaults.removeObject(forKey: "fhint_\(filterId)")
        }
    }

    public func getFolderAutolockSeconds(_ filterId: Int32) -> Int {
        let val = defaults.object(forKey: "fltimer_\(filterId)") as? Int
        return val ?? -1
    }

    public func setFolderAutolockSeconds(_ filterId: Int32, seconds: Int) {
        defaults.set(seconds, forKey: "fltimer_\(filterId)")
    }

    public func getEffectiveFolderAutolockSeconds(_ filterId: Int32) -> Int {
        let s = getFolderAutolockSeconds(filterId)
        return s >= 0 ? s : 300
    }

    public func getAllLockedFolderIds() -> [Int32] {
        let keys = defaults.dictionaryRepresentation().keys
        return keys.compactMap { key -> Int32? in
            guard key.hasPrefix("flk_") else { return nil }
            return Int32(key.dropFirst(4))
        }
    }

    // MARK: - Groups

    public func groupSettingsId(_ groupId: Int) -> Int64 {
        return Self.groupIdOffset + Int64(groupId)
    }

    public func createGroup(name: String, pin: String, chatIds: [Int64]) -> Int {
        let nextId = defaults.integer(forKey: "grp_next_id")
        let groupId = nextId
        defaults.set(nextId + 1, forKey: "grp_next_id")

        defaults.set(name, forKey: "grp_\(groupId)_name")
        let pinHash = hashPin(pin)
        defaults.set(pinHash, forKey: "grp_\(groupId)_pin")
        defaults.set(chatIds.map { "\($0)" }.joined(separator: ","), forKey: "grp_\(groupId)_chats")
        defaults.set(-1, forKey: "grp_\(groupId)_timer")
        defaults.set(-1, forKey: "grp_\(groupId)_hide")

        for cid in chatIds {
            setLockHash(cid, hash: pinHash)
            setChatAutolockSeconds(cid, seconds: -1)
        }
        return groupId
    }

    public func removeGroup(_ groupId: Int) {
        let chats = getGroupChats(groupId)
        for cid in chats {
            removeLock(cid)
        }
        for suffix in ["_name", "_pin", "_chats", "_timer", "_hide", "_hint"] {
            defaults.removeObject(forKey: "grp_\(groupId)\(suffix)")
        }
    }

    public func addChatToGroup(_ groupId: Int, dialogId: Int64) {
        var chats = getGroupChats(groupId)
        guard !chats.contains(dialogId) else { return }
        chats.append(dialogId)
        defaults.set(chats.map { "\($0)" }.joined(separator: ","), forKey: "grp_\(groupId)_chats")
        if let groupHash = defaults.string(forKey: "grp_\(groupId)_pin") {
            setLockHash(dialogId, hash: groupHash)
        }
    }

    public func removeChatFromGroup(_ groupId: Int, dialogId: Int64) {
        var chats = getGroupChats(groupId)
        chats.removeAll { $0 == dialogId }
        defaults.set(chats.map { "\($0)" }.joined(separator: ","), forKey: "grp_\(groupId)_chats")
        removeLock(dialogId)
    }

    public func setGroupPin(_ groupId: Int, newPin: String) {
        let pinHash = hashPin(newPin)
        defaults.set(pinHash, forKey: "grp_\(groupId)_pin")
        for cid in getGroupChats(groupId) {
            setLockHash(cid, hash: pinHash)
        }
    }

    public func checkGroupPin(_ groupId: Int, pin: String) -> Bool {
        guard let stored = defaults.string(forKey: "grp_\(groupId)_pin") else { return false }
        return verifyAndUpgrade(storedHash: stored, pin: pin, prefKey: "grp_\(groupId)_pin")
    }

    public func getGroupName(_ groupId: Int) -> String? {
        return defaults.string(forKey: "grp_\(groupId)_name")
    }

    public func setGroupName(_ groupId: Int, name: String) {
        defaults.set(name, forKey: "grp_\(groupId)_name")
    }

    public func getGroupChats(_ groupId: Int) -> [Int64] {
        guard let str = defaults.string(forKey: "grp_\(groupId)_chats"), !str.isEmpty else { return [] }
        return str.split(separator: ",").compactMap { Int64($0) }
    }

    public func getAllGroupIds() -> [Int] {
        let keys = defaults.dictionaryRepresentation().keys
        var ids = Set<Int>()
        for key in keys {
            guard key.hasPrefix("grp_") else { continue }
            let rest = key.dropFirst(4)
            guard let underscoreIdx = rest.firstIndex(of: "_") else { continue }
            if let gid = Int(rest[rest.startIndex..<underscoreIdx]) {
                ids.insert(gid)
            }
        }
        return Array(ids).sorted()
    }

    public func findGroupForChat(_ dialogId: Int64) -> Int {
        for gid in getAllGroupIds() {
            if getGroupChats(gid).contains(dialogId) {
                return gid
            }
        }
        return -1
    }

    public func getGroupTimer(_ groupId: Int) -> Int {
        let val = defaults.object(forKey: "grp_\(groupId)_timer") as? Int
        return val ?? -1
    }

    public func setGroupTimer(_ groupId: Int, seconds: Int) {
        defaults.set(seconds, forKey: "grp_\(groupId)_timer")
    }

    public func getGroupHide(_ groupId: Int) -> Int {
        let val = defaults.object(forKey: "grp_\(groupId)_hide") as? Int
        return val ?? -1
    }

    public func setGroupHide(_ groupId: Int, value: Int) {
        defaults.set(value, forKey: "grp_\(groupId)_hide")
    }

    public func getGroupHint(_ groupId: Int) -> String? {
        return defaults.string(forKey: "grp_\(groupId)_hint")
    }

    public func setGroupHint(_ groupId: Int, hint: String?) {
        if let h = hint, !h.isEmpty {
            defaults.set(h, forKey: "grp_\(groupId)_hint")
        } else {
            defaults.removeObject(forKey: "grp_\(groupId)_hint")
        }
    }

    // MARK: - Biometric

    public var isBiometricEnabled: Bool {
        get { defaults.bool(forKey: "use_biometric") }
        set { defaults.set(newValue, forKey: "use_biometric") }
    }

    // MARK: - Global

    public var globalAutolockSeconds: Int {
        get {
            let val = defaults.object(forKey: "autolock_seconds") as? Int
            return val ?? 300
        }
        set { defaults.set(newValue, forKey: "autolock_seconds") }
    }
}
