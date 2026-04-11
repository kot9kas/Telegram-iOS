import Foundation

public struct LitegramStrings {
    public let languageCode: String
    private let isRu: Bool

    public init(languageCode: String) {
        self.languageCode = languageCode
        self.isRu = languageCode.hasPrefix("ru")
    }

    // MARK: - Common

    public var ok: String { isRu ? "OK" : "OK" }
    public var cancel: String { isRu ? "Отмена" : "Cancel" }
    public var delete: String { isRu ? "Удалить" : "Delete" }

    // MARK: - PIN Controller

    public var pinEnter: String { isRu ? "Введите PIN-код" : "Enter PIN" }
    public var pinSet: String { isRu ? "Установите PIN-код" : "Set PIN" }
    public var pinConfirm: String { isRu ? "Подтвердите PIN-код" : "Confirm PIN" }
    public var pinMismatch: String { isRu ? "PIN не совпал" : "PINs don't match" }
    public var pinEnterBio: String { isRu ? "Ввести PIN" : "Enter PIN" }
    public var pinUnlockChat: String { isRu ? "Разблокировать чат" : "Unlock chat" }

    // MARK: - Autolock Options

    public var autolockImmediately: String { isRu ? "Сразу" : "Immediately" }
    public var autolock30sec: String { isRu ? "30 секунд" : "30 seconds" }
    public var autolock1min: String { isRu ? "1 минута" : "1 minute" }
    public var autolock3min: String { isRu ? "3 минуты" : "3 minutes" }
    public var autolock5min: String { isRu ? "5 минут" : "5 minutes" }
    public var autolock10min: String { isRu ? "10 минут" : "10 minutes" }
    public var autolock30min: String { isRu ? "30 минут" : "30 minutes" }

    public var autolockOptions: [(title: String, seconds: Int)] {
        [
            (autolockImmediately, 0),
            (autolock30sec, 30),
            (autolock1min, 60),
            (autolock3min, 180),
            (autolock5min, 300),
            (autolock10min, 600),
            (autolock30min, 1800)
        ]
    }

    public func autolockCustomTitle(seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if s == 0 {
            return isRu ? "\(m) мин." : "\(m) min."
        }
        return isRu ? "\(m) мин. \(s) сек." : "\(m) min. \(s) sec."
    }

    public func autolockTitle(for seconds: Int) -> String {
        for opt in autolockOptions where opt.seconds == seconds {
            return opt.title
        }
        return autolockCustomTitle(seconds: seconds)
    }

    // MARK: - Chats Controller (Settings)

    public var chatsTitle: String { isRu ? "Защита чатов" : "Chat Protection" }
    public var chatsSubtitle: String { isRu ? "PIN-защита чатов и папок" : "PIN protection for chats and folders" }
    public var protectedChats: String { isRu ? "Защищённые чаты" : "Protected Chats" }
    public var protectedFolders: String { isRu ? "Защищённые папки" : "Protected Folders" }
    public var biometricFooter: String {
        isRu
            ? "Используйте биометрию для быстрой разблокировки защищённых чатов."
            : "Use biometrics for quick unlock of protected chats."
    }
    public var pinFooter: String {
        isRu
            ? "Установите PIN-код на чат или папку. При открытии защищённого чата потребуется ввод PIN."
            : "Set a PIN on a chat or folder. A PIN will be required to open a protected chat."
    }
    public var unlockWithFaceID: String { isRu ? "Разблокировка по Face ID" : "Unlock with Face ID" }
    public var unlockWithTouchID: String { isRu ? "Разблокировка по Touch ID" : "Unlock with Touch ID" }
    public var autoLock: String { isRu ? "Автоблокировка" : "Auto-Lock" }
    public var autolockFooter: String {
        isRu
            ? "Время бездействия, после которого защищённые чаты будут автоматически заблокированы."
            : "Inactivity time after which protected chats will be automatically locked."
    }
    public var addPassword: String { isRu ? "Добавить пароль" : "Add Password" }
    public var unlock: String { isRu ? "Разблок." : "Unlock" }
    public var enableBiometrics: String { isRu ? "Включить биометрию для защиты чатов" : "Enable biometrics for chat protection" }
    public var customTime: String { isRu ? "Своё время" : "Custom Time" }
    public var enterTimeMinutes: String { isRu ? "Введите время в минутах" : "Enter time in minutes" }
    public var minutes: String { isRu ? "Минуты" : "Minutes" }
    public var addToChat: String { isRu ? "🔒 На чат" : "🔒 Chat" }
    public var addToFolder: String { isRu ? "📁 На папку" : "📁 Folder" }
    public var selectChat: String { isRu ? "Выберите чат" : "Select Chat" }
    public var chatAlreadyProtected: String { isRu ? "Чат уже защищён" : "Chat is already protected" }
    public var noFolders: String { isRu ? "Нет папок" : "No Folders" }
    public var createFolder: String {
        isRu
            ? "Создайте папку чатов в настройках Telegram"
            : "Create a chat folder in Telegram settings"
    }
    public var folderAlreadyProtected: String { isRu ? "Папка уже защищена" : "Folder is already protected" }
    public var changePin: String { isRu ? "🔑 Изменить PIN" : "🔑 Change PIN" }
    public var removeProtection: String { isRu ? "🗑 Снять защиту" : "🗑 Remove Protection" }
    public var chatFallback: String { isRu ? "Чат" : "Chat" }
    public func folderFallback(_ id: Int32) -> String { isRu ? "Папка \(id)" : "Folder \(id)" }

    // MARK: - Context Menu

    public var removePin: String { isRu ? "Снять PIN-код" : "Remove PIN" }
    public var setPin: String { isRu ? "Установить PIN-код" : "Set PIN" }

    // MARK: - Profile Controller

    public var sessionTransferTitle: String { isRu ? "Перенос сессии" : "Session Transfer" }
    public var sessionTransferSubtitle: String { isRu ? "Импорт и экспорт" : "Import and export" }
    public var sessionImport: String { isRu ? "Импорт сессии" : "Import Session" }
    public var sessionImportSubtitle: String { isRu ? "Из файла Pyrogram (.session)" : "From Pyrogram file (.session)" }
    public var sessionExport: String { isRu ? "Экспорт сессии" : "Export Session" }
    public var sessionExportSubtitle: String { isRu ? "Сохранить как Pyrogram (.session)" : "Save as Pyrogram (.session)" }
    public var sessionExportError: String { isRu ? "Ошибка экспорта" : "Export Error" }
    public var sessionExportNoData: String { isRu ? "Не удалось получить данные сессии" : "Could not retrieve session data" }
    public var connectionTitle: String { isRu ? "Соединение" : "Connection" }
    public var connectionSubtitle: String { isRu ? "Настройки прокси и подключение" : "Proxy settings and connection" }
    public var supportTitle: String { isRu ? "Поддержка" : "Support" }
    public var saveTraffic: String { isRu ? "Экономия трафика" : "Save Traffic" }
    public var saveTrafficSubtitle: String { isRu ? "Сжатие изображений и медиа" : "Image and media compression" }
    public var freeBadge: String { isRu ? "Бесплатно" : "Free" }
    public var chatSupport: String { isRu ? "Поддержка в чате" : "Chat Support" }
    public var email: String { isRu ? "Почта" : "Email" }
    public var adOpen: String { isRu ? "Открыть" : "Open" }
    public var adClose: String { isRu ? "Закрыть" : "Close" }
}
