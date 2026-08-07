import Foundation
import Security

enum ThemeChoice: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark
}

enum ValueRendererDisplayMode: String, Codable, CaseIterable, Sendable {
    case diff
    case raw
}

struct AppSettings: Codable, Sendable, Equatable {
    var theme: ThemeChoice = .system
    var topicOrder: TopicOrder = .none
    var highlightTopicUpdates: Bool = true
    var valueRendererDisplayMode: ValueRendererDisplayMode = .diff
    var autoExpandLimit: Int = 0
    var selectTopicWithMouseOver: Bool = false
    var timeLocale: String = Locale.current.identifier
    var topicFilter: String = ""
}

/// Everything persisted lands in one JSON file (settings.json in
/// Application Support). Passwords are the exception: those go to the
/// Keychain.
struct PersistedConfig: Codable {
    var connections: [ConnectionProfile] = []
    var lastSelectedConnection: String?
    var settings: AppSettings = AppSettings()
    /// Chart panel layout per connection id.
    var chartViewStates: [String: [ChartParameters]] = [:]
}

@MainActor
final class SettingsStore {
    static let shared = SettingsStore()

    private var configURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MQTT Explorer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    func load() -> PersistedConfig {
        guard let data = try? Data(contentsOf: configURL) else {
            return PersistedConfig()
        }
        return (try? JSONDecoder().decode(PersistedConfig.self, from: data)) ?? PersistedConfig()
    }

    func save(_ config: PersistedConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }
}

/// Minimal Keychain wrapper for broker passwords: one generic-password item
/// per connection profile.
enum KeychainStore {
    private static let service = "MQTT Explorer Native"

    static func setPassword(_ password: String, for profileId: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileId,
        ]
        SecItemDelete(query as CFDictionary)
        guard !password.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func password(for profileId: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(for profileId: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileId,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
