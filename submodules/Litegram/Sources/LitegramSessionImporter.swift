import Foundation
import sqlcipher
import CryptoKit
import TelegramCore
import Postbox

public struct PyrogramSessionData {
    public let dcId: Int32
    public let authKey: Data
    public let userId: Int64
}

public enum SessionImportError: LocalizedError {
    case cannotOpenFile
    case invalidFormat
    case noSessionData
    case noAuthKey
    case invalidAuthKey

    public var errorDescription: String? {
        switch self {
        case .cannotOpenFile: return "Не удалось открыть файл сессии"
        case .invalidFormat: return "Неверный формат файла"
        case .noSessionData: return "Данные сессии не найдены"
        case .noAuthKey: return "Ключ авторизации отсутствует"
        case .invalidAuthKey: return "Неверный ключ авторизации (должен быть 256 байт)"
        }
    }
}

public enum LitegramSessionImporter {

    public static func parsePyrogramSession(at url: URL) throws -> PyrogramSessionData {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            throw SessionImportError.cannotOpenFile
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let query = "SELECT dc_id, auth_key, user_id FROM sessions LIMIT 1"
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw SessionImportError.invalidFormat
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw SessionImportError.noSessionData
        }

        let dcId = Int32(sqlite3_column_int(stmt, 0))

        guard let authKeyBlob = sqlite3_column_blob(stmt, 1) else {
            throw SessionImportError.noAuthKey
        }
        let authKeyLen = Int(sqlite3_column_bytes(stmt, 1))
        guard authKeyLen == 256 else {
            throw SessionImportError.invalidAuthKey
        }
        let authKey = Data(bytes: authKeyBlob, count: authKeyLen)

        let userId = Int64(sqlite3_column_int64(stmt, 2))

        return PyrogramSessionData(dcId: dcId, authKey: authKey, userId: userId)
    }

    public static func makeBackupData(from session: PyrogramSessionData) -> AccountBackupData {
        let authKeyId = computeAuthKeyId(authKey: session.authKey)
        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(session.userId))

        return AccountBackupData(
            masterDatacenterId: session.dcId,
            peerId: peerId.toInt64(),
            masterDatacenterKey: session.authKey,
            masterDatacenterKeyId: authKeyId,
            notificationEncryptionKeyId: nil,
            notificationEncryptionKey: nil,
            additionalDatacenterKeys: [:]
        )
    }

    public enum SessionExportError: LocalizedError {
        case cannotCreateFile
        case sqliteError(String)

        public var errorDescription: String? {
            switch self {
            case .cannotCreateFile: return "Не удалось создать файл сессии"
            case .sqliteError(let msg): return "Ошибка SQLite: \(msg)"
            }
        }
    }

    public static func exportPyrogramSession(backupData: AccountBackupData) throws -> URL {
        let fileName = "litegram_\(abs(backupData.peerId)).session"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)

        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            throw SessionExportError.cannotCreateFile
        }
        defer { sqlite3_close(db) }

        let createSQL = "CREATE TABLE sessions (dc_id INTEGER, auth_key BLOB, user_id INTEGER)"
        guard sqlite3_exec(db, createSQL, nil, nil, nil) == SQLITE_OK else {
            throw SessionExportError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }

        let insertSQL = "INSERT INTO sessions (dc_id, auth_key, user_id) VALUES (?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw SessionExportError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        let userId = PeerId(backupData.peerId).id._internalGetInt64Value()

        sqlite3_bind_int(stmt, 1, backupData.masterDatacenterId)
        let keyData = backupData.masterDatacenterKey
        keyData.withUnsafeBytes { ptr in
            _ = sqlite3_bind_blob(stmt, 2, ptr.baseAddress, Int32(keyData.count), nil)
        }
        sqlite3_bind_int64(stmt, 3, userId)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SessionExportError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }

        return url
    }

    private static func computeAuthKeyId(authKey: Data) -> Int64 {
        let digest = Insecure.SHA1.hash(data: authKey)
        let hashBytes = Array(digest)
        let offset = hashBytes.count - 8
        var keyId: Int64 = 0
        withUnsafeMutableBytes(of: &keyId) { dst in
            for i in 0..<8 {
                dst[i] = hashBytes[offset + i]
            }
        }
        return keyId
    }
}
