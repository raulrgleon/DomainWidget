import SwiftUI

/// Resumen de un vistazo: vigilancia, caducidades próximas, favoritos y recientes.
struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router

    @State private var query = ""
    @State private var isRefreshing = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    TextField("Busca un nombre…", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .domainInputStyle()
                        .onSubmit(search)
                    Button(action: search) {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section {
                HStack(spacing: 10) {
                    StatCard(value: library.watchlist.count, title: "Vigilando", systemImage: "eye", tint: .blue) {
                        router.selection = .watchlist
                    }
                    StatCard(value: expiringSoon.count, title: "Caducan pronto", systemImage: "exclamationmark.triangle.fill",
                             tint: expiringSoon.isEmpty ? .gray : (hasCritical ? .red : .orange)) {
                        router.selection = .watchlist
                    }
                    StatCard(value: availableNow.count, title: "Libres", systemImage: "checkmark.circle.fill",
                             tint: availableNow.isEmpty ? .gray : .green) {
                        router.selection = .watchlist
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            }

            if !availableNow.isEmpty {
                Section("Ya están libres") {
                    ForEach(availableNow) { item in
                        AvailabilityRow(domain: item.domain, knownStatus: item.lastStatus)
                    }
                }
            }

            if !expiringSoon.isEmpty {
                Section {
                    ForEach(expiringSoon) { item in
                        AvailabilityRow(domain: item.domain, knownStatus: item.lastStatus, expires: item.expires)
                    }
                } header: {
                    Text("Caducan en \(settings.expiryWarningDays) días o menos")
                }
            }

            Section {
                if library.watchlist.isEmpty {
                    EmptyHint(
                        systemImage: "eye",
                        title: "Aún no vigilas ningún dominio",
                        message: "Vigila un dominio ocupado que te guste y te avisamos cuando esté a punto de caducar o quede libre.",
                        actionTitle: "Ir a Vigilancia"
                    ) { router.selection = .watchlist }
                } else {
                    ForEach(watchPreview) { item in
                        AvailabilityRow(domain: item.domain, knownStatus: item.lastStatus, expires: item.expires)
                    }
                    if library.watchlist.count > watchPreview.count {
                        Button("Ver los \(library.watchlist.count)") { router.selection = .watchlist }
                    }
                }
            } header: {
                Text("Vigilando")
            }

            if !library.favorites.isEmpty {
                Section("Favoritos") {
                    ForEach(library.favorites.prefix(5)) { favorite in
                        AvailabilityRow(domain: favorite.domain, knownStatus: favorite.status)
                    }
                    if library.favorites.count > 5 {
                        Button("Ver los \(library.favorites.count)") { router.selection = .favorites }
                    }
                }
            }

            if !library.history.isEmpty {
                Section("Recientes") {
                    ForEach(library.history.prefix(5)) { entry in
                        Button {
                            switch entry.kind {
                            case .availability: router.search(entry.query)
                            case .analysis: router.analyze(entry.query)
                            case .bulk: router.selection = .bulk
                            }
                        } label: {
                            HStack {
                                Label(entry.query, systemImage: entry.kind.systemImage)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(entry.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Inicio")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await refresh() }
                } label: {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Comprobar vigilancia", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(library.watchlist.isEmpty || isRefreshing)
            }
        }
        .refreshable { await refresh() }
        .task(id: library.watchlist.filter { $0.lastChecked == nil }.map(\.domain)) {
            guard !isRefreshing, library.watchlist.contains(where: { $0.lastChecked == nil }) else { return }
            await refresh()
        }
    }

    private var expiringSoon: [WatchItem] {
        library.watchlist
            .filter { item in
                guard item.lastStatus?.isAvailable != true, let expires = item.expires else { return false }
                return ExpiryUrgency.level(for: expires, warningDays: settings.expiryWarningDays).isUrgent
            }
            .sorted { ($0.expires ?? .distantFuture) < ($1.expires ?? .distantFuture) }
    }

    private var hasCritical: Bool {
        expiringSoon.contains { item in
            item.expires.map { ExpiryUrgency.level(for: $0, warningDays: settings.expiryWarningDays) != .warning } ?? false
        }
    }

    private var availableNow: [WatchItem] {
        library.watchlist.filter { $0.lastStatus?.isAvailable == true }
    }

    private var watchPreview: [WatchItem] {
        let highlighted = Set((expiringSoon + availableNow).map(\.domain))
        return Array(library.watchlist.filter { !highlighted.contains($0.domain) }.prefix(5))
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        query = ""
        router.search(text)
    }

    private func refresh() async {
        isRefreshing = true
        await WatchlistMonitor.runCheck(library: library, settings: settings)
        isRefreshing = false
    }
}

struct StatCard: View {
    let value: Int
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                Text("\(value)")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

/// Estado vacío compacto con explicación y acción, para usar dentro de listas.
struct EmptyHint: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.bordered)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
