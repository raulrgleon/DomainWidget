import SwiftUI

struct FavoritesView: View {
    @Environment(LibraryStore.self) private var library
    @State private var results: [String: DomainAvailability] = [:]
    @State private var isChecking = false

    var body: some View {
        List {
            ForEach(library.favorites) { favorite in
                AvailabilityRow(
                    domain: favorite.domain,
                    result: results[favorite.domain],
                    knownStatus: favorite.status,
                    isPending: isChecking
                )
            }
            .onDelete { library.removeFavorites(at: $0) }
        }
        .overlay {
            if library.favorites.isEmpty {
                ContentUnavailableView(
                    "Sin favoritos",
                    systemImage: "star",
                    description: Text("Marca dominios con la estrella para guardarlos en tu lista corta.")
                )
            }
        }
        .navigationTitle("Favoritos")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: recheck) {
                    Label("Recomprobar", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(library.favorites.isEmpty || isChecking)
                ShareLink(item: library.favorites.map(\.domain).joined(separator: "\n")) {
                    Label("Compartir", systemImage: "square.and.arrow.up")
                }
                .disabled(library.favorites.isEmpty)
            }
        }
    }

    private func recheck() {
        isChecking = true
        results = [:]
        let domains = library.favorites.map(\.domain)
        Task {
            let all = await AvailabilityService().check(domains: domains, useCache: false) { result in
                results[result.domain] = result
            }
            all.forEach(library.updateFavoriteStatus)
            isChecking = false
        }
    }
}

struct HistoryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @State private var confirmClear = false

    var body: some View {
        List {
            ForEach(library.history) { entry in
                Button {
                    open(entry)
                } label: {
                    HStack {
                        Image(systemName: entry.kind.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.query).foregroundStyle(.primary)
                            Text("\(entry.kind.label) · \(entry.summary)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete { library.removeHistory(at: $0) }
        }
        .overlay {
            if library.history.isEmpty {
                ContentUnavailableView("Sin historial", systemImage: "clock", description: Text("Tus búsquedas y análisis aparecerán aquí."))
            }
        }
        .navigationTitle("Historial")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    Label("Borrar historial", systemImage: "trash")
                }
                .disabled(library.history.isEmpty)
            }
        }
        .confirmationDialog("¿Borrar todo el historial?", isPresented: $confirmClear) {
            Button("Borrar", role: .destructive) { library.clearHistory() }
        }
    }

    private func open(_ entry: HistoryEntry) {
        switch entry.kind {
        case .availability: router.search(entry.query)
        case .analysis: router.analyze(entry.query)
        case .bulk: router.selection = .bulk
        }
    }
}

struct WatchlistView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppSettings.self) private var settings

    @State private var newDomain = ""
    @State private var isChecking = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("dominio.com", text: $newDomain)
                        .domainInputStyle()
                        .onSubmit(add)
                    Button("Vigilar", action: add)
                        .disabled(newDomain.isEmpty)
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text(footer)
            }

            if !library.watchlist.isEmpty {
                Section("Vigilando") {
                    ForEach(library.watchlist) { item in
                        AvailabilityRow(domain: item.domain, knownStatus: item.lastStatus, isPending: isChecking, detail: detail(for: item))
                    }
                    .onDelete { library.removeWatch(at: $0) }
                }
            }
        }
        .navigationTitle("Vigilancia")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: checkNow) {
                    Label("Comprobar ahora", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(library.watchlist.isEmpty || isChecking)
            }
        }
    }

    private var footer: String {
        #if os(macOS)
        "Se comprueba cada 6 horas mientras la app está abierta (también desde la barra de menú). Avisa cuando un dominio queda libre o le quedan \(settings.expiryWarningDays) días o menos para caducar."
        #else
        "Se comprueba al abrir la app y en segundo plano cuando iOS lo permite (no hay hora garantizada). Avisa cuando un dominio queda libre o le quedan \(settings.expiryWarningDays) días o menos para caducar."
        #endif
    }

    private func detail(for item: WatchItem) -> String {
        var parts: [String] = []
        if let expires = item.expires {
            parts.append("Caduca \(expires.formatted(date: .abbreviated, time: .omitted))")
        }
        if let checked = item.lastChecked {
            parts.append("Revisado \(checked.formatted(.relative(presentation: .named)))")
        } else {
            parts.append("Sin revisar")
        }
        return parts.joined(separator: " · ")
    }

    private func add() {
        guard let domain = DomainLookupService.normalizeDomain(newDomain) else {
            message = LookupError.invalidDomain.localizedDescription
            return
        }
        newDomain = ""
        message = nil
        if !library.isWatched(domain) {
            library.toggleWatch(domain)
        }
        Task {
            _ = await WatchlistMonitor.requestNotificationPermission()
            checkNow()
        }
    }

    private func checkNow() {
        isChecking = true
        Task {
            let sent = await WatchlistMonitor.runCheck(library: library, settings: settings)
            isChecking = false
            message = sent > 0 ? "\(sent) avisos enviados." : "Comprobado \(Date().formatted(date: .omitted, time: .shortened))."
        }
    }
}
