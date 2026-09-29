import SwiftUI
import Observation

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case search, analyze, bulk, favorites, history, watchlist, settings

    var id: String { rawValue }

    var title: String {
        switch self {
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
        case .search: return "1"
        case .analyze: return "2"
        case .bulk: return "3"
        case .favorites: return "4"
        case .history: return "5"
        case .watchlist: return "6"
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
    var selection: SidebarItem? = .search {
        didSet { if oldValue != selection { path = [] } }
    }
    var path: [DomainRoute] = []
    var pendingSearch: String?

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
}

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library
    @Environment(NetworkMonitor.self) private var network

    var body: some View {
        @Bindable var router = router
        NavigationSplitView {
            List(selection: $router.selection) {
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
                detail(for: router.selection ?? .search)
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
