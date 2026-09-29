import Foundation
import Observation

struct SavedDomain: Identifiable, Codable, Hashable {
    var id: String { domain }
    let domain: String
    var status: AvailabilityStatus?
    var note: String = ""
    var addedAt: Date = Date()
}

struct HistoryEntry: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case availability, analysis, bulk

        var label: String {
            switch self {
            case .availability: return "Búsqueda"
            case .analysis: return "Análisis"
            case .bulk: return "Masivo"
            }
        }

        var systemImage: String {
            switch self {
            case .availability: return "magnifyingglass"
            case .analysis: return "doc.text.magnifyingglass"
            case .bulk: return "list.bullet"
            }
        }
    }

    var id = UUID()
    let query: String
    let kind: Kind
    var date = Date()
    var summary: String
}

struct WatchItem: Identifiable, Codable, Hashable {
    var id: String { domain }
    let domain: String
    var lastStatus: AvailabilityStatus?
    var expires: Date?
    var lastChecked: Date?
    var notifiedExpiry: Date?
    var addedAt = Date()
}

/// Favoritos, historial y vigilancia. Se guardan en local y, si la app tiene iCloud, se sincronizan
/// entre Mac e iPhone con NSUbiquitousKeyValueStore (última escritura gana por lista).
@Observable
@MainActor
final class LibraryStore {
    private(set) var favorites: [SavedDomain] = []
    private(set) var history: [HistoryEntry] = []
    private(set) var watchlist: [WatchItem] = []

    private static let historyLimit = 200
    private let defaults: UserDefaults
    private let cloud = NSUbiquitousKeyValueStore.default

    private enum Key: String, CaseIterable {
        case favorites = "library.favorites"
        case history = "library.history"
        case watchlist = "library.watchlist"

        var stampKey: String { rawValue + ".modified" }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favorites = load(.favorites) ?? []
        history = load(.history) ?? []
        watchlist = load(.watchlist) ?? []

        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.mergeFromCloud() }
        }
        cloud.synchronize()
        mergeFromCloud()
    }

    // MARK: Favoritos

    func isFavorite(_ domain: String) -> Bool {
        favorites.contains { $0.domain == domain }
    }

    func toggleFavorite(_ domain: String, status: AvailabilityStatus? = nil) {
        if let index = favorites.firstIndex(where: { $0.domain == domain }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(SavedDomain(domain: domain, status: status), at: 0)
        }
        save(.favorites, favorites)
    }

    func updateNote(_ note: String, for domain: String) {
        guard let index = favorites.firstIndex(where: { $0.domain == domain }) else { return }
        favorites[index].note = note
        save(.favorites, favorites)
    }

    func updateFavoriteStatus(_ result: DomainAvailability) {
        guard let index = favorites.firstIndex(where: { $0.domain == result.domain }),
              favorites[index].status != result.status else { return }
        favorites[index].status = result.status
        save(.favorites, favorites)
    }

    func removeFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        save(.favorites, favorites)
    }

    // MARK: Historial

    func recordHistory(query: String, kind: HistoryEntry.Kind, summary: String) {
        history.removeAll { $0.query == query && $0.kind == kind }
        history.insert(HistoryEntry(query: query, kind: kind, summary: summary), at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
        save(.history, history)
    }

    func removeHistory(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        save(.history, history)
    }

    func clearHistory() {
        history.removeAll()
        save(.history, history)
    }

    // MARK: Vigilancia

    func isWatched(_ domain: String) -> Bool {
        watchlist.contains { $0.domain == domain }
    }

    func toggleWatch(_ domain: String, status: AvailabilityStatus? = nil, expires: Date? = nil) {
        if let index = watchlist.firstIndex(where: { $0.domain == domain }) {
            watchlist.remove(at: index)
        } else {
            watchlist.insert(WatchItem(domain: domain, lastStatus: status, expires: expires), at: 0)
        }
        save(.watchlist, watchlist)
    }

    func removeWatch(at offsets: IndexSet) {
        watchlist.remove(atOffsets: offsets)
        save(.watchlist, watchlist)
    }

    func updateWatch(_ item: WatchItem) {
        guard let index = watchlist.firstIndex(where: { $0.domain == item.domain }) else { return }
        watchlist[index] = item
        save(.watchlist, watchlist)
    }

    // MARK: Persistencia

    private func load<T: Decodable>(_ key: Key) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ key: Key, _ value: T) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let stamp = Date().timeIntervalSince1970
        defaults.set(data, forKey: key.rawValue)
        defaults.set(stamp, forKey: key.stampKey)
        cloud.set(data, forKey: key.rawValue)
        cloud.set(stamp, forKey: key.stampKey)
    }

    private func mergeFromCloud() {
        for key in Key.allCases {
            let remoteStamp = cloud.double(forKey: key.stampKey)
            guard remoteStamp > defaults.double(forKey: key.stampKey),
                  let data = cloud.data(forKey: key.rawValue) else { continue }
            defaults.set(data, forKey: key.rawValue)
            defaults.set(remoteStamp, forKey: key.stampKey)
            let decoder = JSONDecoder()
            switch key {
            case .favorites: favorites = (try? decoder.decode([SavedDomain].self, from: data)) ?? favorites
            case .history: history = (try? decoder.decode([HistoryEntry].self, from: data)) ?? history
            case .watchlist: watchlist = (try? decoder.decode([WatchItem].self, from: data)) ?? watchlist
            }
        }
    }
}
