import Foundation
import Network
import Observation
import UserNotifications
#if os(iOS)
import BackgroundTasks
#endif

@Observable
@MainActor
final class NetworkMonitor {
    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }
}

/// Revisa la lista de vigilancia y avisa cuando un dominio queda libre o está a punto de caducar.
@MainActor
enum WatchlistMonitor {
    static let taskIdentifier = "com.raul.DomainWidget.watchlist"
    static let checkInterval: TimeInterval = 60 * 60 * 6

    static func requestNotificationPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    @discardableResult
    static func runCheck(library: LibraryStore, settings: AppSettings) async -> Int {
        let items = library.watchlist
        guard !items.isEmpty else { return 0 }

        let results = await AvailabilityService(maxConcurrent: 3).check(domains: items.map(\.domain), useCache: false)
        var notifications = 0
        for result in results {
            guard var item = library.watchlist.first(where: { $0.domain == result.domain }) else { continue }
            let previous = item.lastStatus

            if result.status != .unknown {
                item.lastStatus = result.status
                item.expires = result.expires ?? item.expires
            }
            item.lastChecked = Date()

            if settings.watchNotifications {
                if result.status.isAvailable, let previous, !previous.isAvailable {
                    await notify(title: "\(item.domain) está disponible", body: "Ya no aparece registrado. Regístralo antes que otro.", id: "available-\(item.domain)")
                    notifications += 1
                } else if let expires = item.expires, item.notifiedExpiry != expires,
                          let days = Calendar.current.dateComponents([.day], from: Date(), to: expires).day,
                          days >= 0, days <= settings.expiryWarningDays {
                    await notify(title: "\(item.domain) caduca pronto", body: "Caduca en \(days) días (\(expires.formatted(date: .abbreviated, time: .omitted))).", id: "expiry-\(item.domain)")
                    item.notifiedExpiry = expires
                    notifications += 1
                }
            }
            library.updateWatch(item)
            library.updateFavoriteStatus(result)
        }
        return notifications
    }

    private static func notify(title: String, body: String, id: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    #if os(iOS)
    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: checkInterval)
        try? BGTaskScheduler.shared.submit(request)
    }
    #endif
}
