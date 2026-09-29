import Foundation
import Observation
import Security

@Observable
@MainActor
final class AppSettings {
    private let defaults: UserDefaults

    var selectedTLDs: [String] { didSet { defaults.set(selectedTLDs, forKey: "settings.selectedTLDs") } }
    var customTLDs: [String] { didSet { defaults.set(customTLDs, forKey: "settings.customTLDs") } }
    var bulkDefaultTLD: String { didSet { defaults.set(bulkDefaultTLD, forKey: "settings.bulkDefaultTLD") } }
    var expiryWarningDays: Int { didSet { defaults.set(expiryWarningDays, forKey: "settings.expiryWarningDays") } }
    var watchNotifications: Bool { didSet { defaults.set(watchNotifications, forKey: "settings.watchNotifications") } }
    var aiEndpoint: String { didSet { defaults.set(aiEndpoint, forKey: "settings.aiEndpoint") } }
    var aiModel: String { didSet { defaults.set(aiModel, forKey: "settings.aiModel") } }
    var affiliateParameters: [String: String] { didSet { defaults.set(affiliateParameters, forKey: "settings.affiliate") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedTLDs = defaults.stringArray(forKey: "settings.selectedTLDs") ?? ["com", "net", "io", "ai", "app", "dev", "co", "bio"]
        customTLDs = defaults.stringArray(forKey: "settings.customTLDs") ?? []
        bulkDefaultTLD = defaults.string(forKey: "settings.bulkDefaultTLD") ?? "com"
        expiryWarningDays = defaults.object(forKey: "settings.expiryWarningDays") as? Int ?? 30
        watchNotifications = defaults.object(forKey: "settings.watchNotifications") as? Bool ?? true
        aiEndpoint = defaults.string(forKey: "settings.aiEndpoint") ?? "https://api.openai.com/v1/chat/completions"
        aiModel = defaults.string(forKey: "settings.aiModel") ?? "gpt-4o-mini"
        affiliateParameters = defaults.dictionary(forKey: "settings.affiliate") as? [String: String] ?? [:]
    }

    var allTLDs: [String] {
        var seen = Set<String>()
        return (DomainName.defaultTLDs + customTLDs).filter { seen.insert($0).inserted }
    }

    func toggleTLD(_ tld: String) {
        if let index = selectedTLDs.firstIndex(of: tld) {
            selectedTLDs.remove(at: index)
        } else {
            selectedTLDs.append(tld)
        }
    }

    func addCustomTLD(_ raw: String) {
        let tld = raw.trimmingCharacters(in: .whitespaces).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !tld.isEmpty, tld.range(of: #"^[a-z0-9-]+(\.[a-z0-9-]+)?$"#, options: .regularExpression) != nil else { return }
        if !allTLDs.contains(tld) { customTLDs.append(tld) }
        if !selectedTLDs.contains(tld) { selectedTLDs.append(tld) }
    }

    var aiAPIKey: String? {
        get { Keychain.read(account: "ai-api-key") }
        set {
            if let newValue, !newValue.isEmpty {
                Keychain.save(newValue, account: "ai-api-key")
            } else {
                Keychain.delete(account: "ai-api-key")
            }
        }
    }

    var aiClient: AISuggestionClient? {
        guard let key = aiAPIKey, let url = URL(string: aiEndpoint), url.scheme == "https" else { return nil }
        return AISuggestionClient(endpoint: url, model: aiModel, apiKey: key)
    }
}

/// Envoltorio mínimo del Llavero para secretos (nunca en UserDefaults ni en el repo).
enum Keychain {
    private static let service = "com.raul.DomainWidget"

    static func save(_ value: String, account: String) {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: Data(value.utf8)
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
