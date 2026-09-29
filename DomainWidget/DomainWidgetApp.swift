import SwiftUI

@MainActor
final class AppServices {
    let library = LibraryStore()
    let settings = AppSettings()
    let network = NetworkMonitor()
    let router = AppRouter()
    private var lastWatchCheck: Date?

    init() {
        #if os(macOS)
        Task { [weak self] in
            while let self {
                await self.checkWatchlistIfStale(minInterval: 60)
                try? await Task.sleep(nanoseconds: UInt64(WatchlistMonitor.checkInterval * 1_000_000_000))
            }
        }
        #endif
    }

    func checkWatchlistIfStale(minInterval: TimeInterval = 60 * 60) async {
        if let last = lastWatchCheck, Date().timeIntervalSince(last) < minInterval { return }
        lastWatchCheck = Date()
        await WatchlistMonitor.runCheck(library: library, settings: settings)
    }
}

@main
struct DomainWidgetApp: App {
    @State private var services = AppServices()
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif

    var body: some Scene {
        #if os(macOS)
        Window("Datos de dominio", id: "main") {
            withServices(RootView())
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandMenu("Ir") {
                ForEach(SidebarItem.sidebarItems) { item in
                    if let shortcut = item.shortcut {
                        Button(item.title) { services.router.selection = item }
                            .keyboardShortcut(shortcut, modifiers: .command)
                    }
                }
            }
        }

        MenuBarExtra("Datos de dominio", systemImage: "globe.desk") {
            withServices(ContentView())
                .frame(width: 420, height: 580)
        }
        .menuBarExtraStyle(.window)

        Settings {
            withServices(SettingsView())
                .frame(width: 540, height: 640)
        }
        #else
        WindowGroup {
            withServices(RootView())
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        Task { await services.checkWatchlistIfStale() }
                    case .background:
                        WatchlistMonitor.scheduleBackgroundRefresh()
                    default:
                        break
                    }
                }
        }
        .backgroundTask(.appRefresh(WatchlistMonitor.taskIdentifier)) {
            await refreshWatchlistInBackground()
        }
        #endif
    }

    private func withServices<V: View>(_ view: V) -> some View {
        view
            .environment(services.library)
            .environment(services.settings)
            .environment(services.network)
            .environment(services.router)
    }

    #if os(iOS)
    private func refreshWatchlistInBackground() async {
        WatchlistMonitor.scheduleBackgroundRefresh()
        await services.checkWatchlistIfStale(minInterval: 60)
    }
    #endif
}
