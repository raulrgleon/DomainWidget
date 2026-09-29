import SwiftUI
import Observation

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case home, search, analyze, bulk, favorites, history, watchlist, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Inicio"
        case .search: return "Buscar"
        case .analyze: return "Analizar"
        case .bulk: return "Masivo"
        case .favorites: return "Favoritos"
        case .history: return "Historial"
        case .watchlist: return "Vigilancia"
        case .settings: return "Ajustes"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .search: return "magnifyingglass"
        case .analyze: return "doc.text.magnifyingglass"
        case .bulk: return "list.bullet.rectangle"
        case .favorites: return "star"
        case .history: return "clock"
        case .watchlist: return "eye"
        case .settings: return "gearshape"
        }
    }

    var shortcut: KeyEquivalent? {
        switch self {
        case .home: return "1"
        case .search: return "2"
        case .analyze: return "3"
        case .bulk: return "4"
        case .favorites: return "5"
        case .history: return "6"
        case .watchlist: return "7"
        case .settings: return nil
        }
    }

    static var sidebarItems: [SidebarItem] {
        #if os(macOS)
        return allCases.filter { $0 != .settings }
        #else
        return allCases
        #endif
    }
}

@Observable
@MainActor
final class AppRouter {
    var selection: SidebarItem? = .home {
        didSet { if oldValue != selection { path = [] } }
    }
    var path: [DomainRoute] = []
    var pendingSearch: String?
    var pendingAnalyze: String?

    func analyze(_ domain: String) {
        if path.last?.domain != domain {
            path.append(DomainRoute(domain: domain))
        }
    }

    func search(_ query: String) {
        pendingSearch = query
        selection = .search
        path = []
    }

    /// domainwidget://buscar?q=nombre · analizar?d=dominio.com · vigilar?d=dominio.com · ir?s=watchlist
    func handle(_ url: URL, library: LibraryStore) {
        guard url.scheme == "domainwidget",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return }
        let value = items.first { ["q", "d", "s"].contains($0.name) }?.value ?? ""
        guard !value.isEmpty else { return }
        switch url.host {
        case "buscar", "search":
            search(value)
        case "analizar", "analyze":
            pendingAnalyze = value
            selection = .analyze
        case "vigilar", "watch":
            if let domain = DomainLookupService.normalizeDomain(value), !library.isWatched(domain) {
                library.toggleWatch(domain)
            }
            selection = .watchlist
        case "ir", "go":
            if let item = SidebarItem(rawValue: value) { selection = item }
        default:
            break
        }
    }
}

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library
    @Environment(NetworkMonitor.self) private var network
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var router = router
        NavigationSplitView {
            List(selection: $router.selection) {
                row(.home, badge: urgentCount)
                Section("Dominios") {
                    row(.search)
                    row(.analyze)
                    row(.bulk)
                }
                Section("Biblioteca") {
                    row(.favorites, badge: library.favorites.count)
                    row(.history)
                    row(.watchlist, badge: library.watchlist.count)
                }
                if SidebarItem.sidebarItems.contains(.settings) {
                    Section {
                        row(.settings)
                    }
                }
            }
            .navigationTitle("Dominios")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            NavigationStack(path: $router.path) {
                detail(for: router.selection ?? .home)
                    .navigationDestination(for: DomainRoute.self) { route in
                        DomainReportScreen(domain: route.domain)
                    }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !network.isOnline {
                    Label("Sin conexión: las consultas fallarán hasta que vuelva la red.", systemImage: "wifi.slash")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(.orange.opacity(0.2))
                }
            }
        }
        .onOpenURL { router.handle($0, library: library) }
    }

    private var urgentCount: Int {
        library.watchlist.filter { item in
            item.lastStatus?.isAvailable == true
                || item.expires.map { ExpiryUrgency.level(for: $0, warningDays: settings.expiryWarningDays).isUrgent } == true
        }.count
    }

    private func row(_ item: SidebarItem, badge: Int = 0) -> some View {
        NavigationLink(value: item) {
            Label(item.title, systemImage: item.systemImage)
        }
        .badge(badge)
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .home: HomeView()
        case .search: SearchView()
        case .analyze: AnalyzeView()
        case .bulk: BulkView()
        case .favorites: FavoritesView()
        case .history: HistoryView()
        case .watchlist: WatchlistView()
        case .settings: SettingsView()
        }
    }
}
