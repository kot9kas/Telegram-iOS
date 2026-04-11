import Foundation
import CryptoKit

public final class LitegramChatLocks {
    public static let shared = LitegramChatLocks()
    public static let autolockDidExpireNotification = Notification.Name("LitegramChatLocksAutolockExpired")

    private var defaults: UserDefaults
    private var unlockTimes: [Int64: Date] = [:]
    private var relockTimers: [Int64: DispatchWorkItem] = [:]
    private var bypassPeers = Set<Int64>()
    public var currentlyViewingLockedPeerId: Int64?
    private var _currentAccountId: Int64?
    private var _salt: Data?

    private init() {
        defaults = UserDefaults(suiteName: "litegram.chatlocks") ?? .standard
    }

    public func setCurrentAccount(id: Int64) {
        guard _currentAccountId != id else { return }
        _currentAccountId = id
        cancelAllRelockTimers()
        unlockTimes.removeAll()
        bypassPeers.removeAll()
        currentlyViewingLockedPeerId = nil
        _salt = nil
        defaults = UserDefaults(suiteName: "litegram.chatlocks.\(id)") ?? .standard
    }

    // MARK: - Biometric

    public var isBiometricEnabled: Bool {
        get { defaults.bool(forKey: "lck_bio") }
        set { defaults.set(newValue, forKey: "lck_bio") }
    }

    // MARK: - Autolock

    public static func autolockOptions(strings: LitegramStrings) -> [(title: String, seconds: Int)] {
        return strings.autolockOptions
    }

    public var autolockSeconds: Int {
        get {
            let v = defaults.object(forKey: "lck_autolock") as? Int
            return v ?? 300
        }
        set {
            defaults.set(newValue, forKey: "lck_autolock")
            unlockTimes.removeAll()
            bypassPeers.removeAll()
            cancelAllRelockTimers()
            NotificationCenter.default.post(name: Self.autolockDidExpireNotification, object: nil)
        }
    }

    public func autolockTitle(strings: LitegramStrings) -> String {
        return strings.autolockTitle(for: autolockSeconds)
    }

    // MARK: - Salt

    private var salt: Data {
        if let s = _salt { return s }
        if let existing = defaults.data(forKey: "lck_salt") {
            _salt = existing
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let s = Data(bytes)
        defaults.set(s, forKey: "lck_salt")
        _salt = s
        return s
    }

    private func hashPin(_ pin: String) -> String {
        let input = Data((pin + salt.base64EncodedString()).utf8)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Chat Locks

    private func loadIds(_ key: String) -> [Int64] {
        guard let data = defaults.data(forKey: key),
              let ids = try? JSONDecoder().decode([Int64].self, from: data) else { return [] }
        return ids
    }

    private func saveIds(_ ids: [Int64], _ key: String) {
        defaults.set(try? JSONEncoder().encode(ids), forKey: key)
    }

    public func lockedChatIds() -> [Int64] {
        return loadIds("lck_chats")
    }

    public func isLocked(_ peerId: Int64) -> Bool {
        return lockedChatIds().contains(peerId)
    }

    public func setLock(_ peerId: Int64, pin: String) {
        var ids = lockedChatIds()
        if !ids.contains(peerId) { ids.append(peerId) }
        saveIds(ids, "lck_chats")
        defaults.set(hashPin(pin), forKey: "lck_p_\(peerId)")
    }

    public func removeLock(_ peerId: Int64) {
        var ids = lockedChatIds()
        ids.removeAll { $0 == peerId }
        saveIds(ids, "lck_chats")
        defaults.removeObject(forKey: "lck_p_\(peerId)")
        unlockTimes.removeValue(forKey: peerId)
    }

    public func checkPin(_ peerId: Int64, pin: String) -> Bool {
        guard let stored = defaults.string(forKey: "lck_p_\(peerId)") else { return false }
        return stored == hashPin(pin)
    }

    // MARK: - Folder Locks

    private func loadFolderIds() -> [Int32] {
        guard let data = defaults.data(forKey: "lck_folders"),
              let ids = try? JSONDecoder().decode([Int32].self, from: data) else { return [] }
        return ids
    }

    private func saveFolderIds(_ ids: [Int32]) {
        defaults.set(try? JSONEncoder().encode(ids), forKey: "lck_folders")
    }

    public func lockedFolderIds() -> [Int32] {
        return loadFolderIds()
    }

    public func isFolderLocked(_ filterId: Int32) -> Bool {
        return lockedFolderIds().contains(filterId)
    }

    public func setFolderLock(_ filterId: Int32, pin: String) {
        var ids = lockedFolderIds()
        if !ids.contains(filterId) { ids.append(filterId) }
        saveFolderIds(ids)
        defaults.set(hashPin(pin), forKey: "lck_fp_\(filterId)")
    }

    public func removeFolderLock(_ filterId: Int32) {
        var ids = lockedFolderIds()
        ids.removeAll { $0 == filterId }
        saveFolderIds(ids)
        defaults.removeObject(forKey: "lck_fp_\(filterId)")
        let key = Int64(filterId) | (1 << 40)
        unlockTimes.removeValue(forKey: key)
    }

    public func checkFolderPin(_ filterId: Int32, pin: String) -> Bool {
        guard let stored = defaults.string(forKey: "lck_fp_\(filterId)") else { return false }
        return stored == hashPin(pin)
    }

    // MARK: - Unlock State

    public func markUnlocked(_ peerId: Int64) {
        unlockTimes[peerId] = Date()
        bypassPeers.insert(peerId)
        scheduleRelockTimer(key: peerId)
    }

    public func isUnlockedNow(_ peerId: Int64) -> Bool {
        if bypassPeers.remove(peerId) != nil { return true }
        guard let t = unlockTimes[peerId] else { return false }
        return Date().timeIntervalSince(t) < Double(autolockSeconds)
    }

    public func markFolderUnlocked(_ filterId: Int32) {
        let key = Int64(filterId) | (1 << 40)
        unlockTimes[key] = Date()
        bypassPeers.insert(key)
        scheduleRelockTimer(key: key)
    }

    public func isFolderUnlockedNow(_ filterId: Int32) -> Bool {
        let key = Int64(filterId) | (1 << 40)
        if bypassPeers.remove(key) != nil { return true }
        guard let t = unlockTimes[key] else { return false }
        return Date().timeIntervalSince(t) < Double(autolockSeconds)
    }

    private func scheduleRelockTimer(key: Int64) {
        relockTimers[key]?.cancel()
        let seconds = autolockSeconds
        guard seconds > 0 else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: LitegramChatLocks.autolockDidExpireNotification, object: nil)
            }
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.relockTimers.removeValue(forKey: key)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: LitegramChatLocks.autolockDidExpireNotification, object: nil)
            }
        }
        relockTimers[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds), execute: work)
    }

    public func cancelAllRelockTimers() {
        for (_, work) in relockTimers {
            work.cancel()
        }
        relockTimers.removeAll()
    }

    public func hasExpiredUnlocks() -> Bool {
        let timeout = Double(autolockSeconds)
        let now = Date()
        for (_, time) in unlockTimes {
            if now.timeIntervalSince(time) >= timeout {
                return true
            }
        }
        return false
    }

    public var hasAnyLock: Bool {
        return !lockedChatIds().isEmpty || !lockedFolderIds().isEmpty
    }
}
