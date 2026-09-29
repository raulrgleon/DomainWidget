import SwiftUI

/// Busca un nombre en muchas extensiones a la vez y propone variaciones.
struct SearchView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router

    @State private var query = ""
    @State private var domains: [String] = []
    @State private var results: [String: DomainAvailability] = [:]
    @State private var isChecking = false
    @State private var availableFirst = false
    @State private var ideas: [String] = []
    @State private var ideaResults: [String: DomainAvailability] = [:]
    @State private var isCheckingIdeas = false
    @State private var isLoadingAI = false
    @State private var message: String?
    @State private var showExporter = false
    @State private var searchTask: Task<Void, Never>?
    @State private var alternatives: [DomainAvailability] = []
    @State private var isFindingAlternatives = false
    @FocusState private var fieldFocused: Bool

    private var ideaTLD: String { settings.selectedTLDs.first ?? "com" }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Nombre o dominio (ej. cafeteria)", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .domainInputStyle()
                    .focused($fieldFocused)
                    .onSubmit(search)
                Button("Buscar", action: search)
                    .buttonStyle(.borderedProminent)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            TLDPicker()
            if let message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    var body: some View {
        List {
            if allTaken {
                Section {
                    if isFindingAlternatives && alternatives.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Buscando alternativas libres…")
                                .foregroundStyle(.secondary)
                        }
                    } else if alternatives.isEmpty {
                        Text("No encontramos alternativas libres cercanas. Prueba las ideas de abajo\(settings.aiClient == nil ? "" : " o pide más con IA").")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(alternatives) { alternative in
                        AvailabilityRow(domain: alternative.domain, result: alternative)
                    }
                } header: {
                    Label("Todo está ocupado · alternativas libres", systemImage: "lightbulb.fill")
                        .foregroundStyle(.orange)
                } footer: {
                    Text("Otras extensiones con el mismo nombre y variaciones en .\(ideaTLD) que sí están disponibles.")
                }
            }

            if !domains.isEmpty {
                Section {
                    if isChecking {
                        ProgressView(value: Double(results.count), total: Double(max(domains.count, 1)))
                    }
                    ForEach(orderedDomains, id: \.self) { domain in
                        AvailabilityRow(domain: domain, result: results[domain], isPending: isChecking)
                    }
                } header: {
                    Text(summary)
                } footer: {
                    Text("«Disponible» y «Ocupado» vienen del registro oficial (RDAP). «Probablemente» indica que esa extensión no tiene RDAP público y se dedujo por DNS. El precio y si es premium lo confirma el registrador.")
                }
            }

            if !ideas.isEmpty {
                Section {
                    ForEach(ideas, id: \.self) { idea in
                        let domain = "\(idea).\(ideaTLD)"
                        AvailabilityRow(
                            domain: domain,
                            result: ideaResults[domain],
                            isPending: isCheckingIdeas,
                            onTap: {
                                query = idea
                                search()
                            }
                        )
                    }
                } header: {
                    HStack {
                        Text("Ideas")
                        Spacer()
                        Button(isCheckingIdeas ? "Comprobando…" : "Comprobar en .\(ideaTLD)", action: checkIdeas)
                            .disabled(isCheckingIdeas)
                            .font(.caption)
                        if settings.aiClient != nil {
                            Button(isLoadingAI ? "Pensando…" : "Más con IA", action: loadAIIdeas)
                                .disabled(isLoadingAI)
                                .font(.caption)
                        }
                    }
                } footer: {
                    Text(settings.aiClient == nil
                         ? "Toca una idea para buscarla en todas las extensiones. Añade una clave de IA en Ajustes para obtener más ideas."
                         : "Toca una idea para buscarla en todas las extensiones.")
                }
            }

            if domains.isEmpty && ideas.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Busca un nombre",
                        systemImage: "magnifyingglass",
                        description: Text("Escribe un nombre y comprobamos a la vez si está libre en .com, .io, .ai, .app y el resto de extensiones marcadas.")
                    )
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            searchBar
        }
        .navigationTitle("Buscar dominios")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $availableFirst) {
                    Label("Libres primero", systemImage: "arrow.up.arrow.down")
                }
                .disabled(domains.isEmpty)
                Button {
                    showExporter = true
                } label: {
                    Label("Exportar CSV", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(results.isEmpty)
                ShareLink(item: csv) {
                    Label("Compartir", systemImage: "square.and.arrow.up")
                }
                .disabled(results.isEmpty)
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: CSVDocument(text: csv),
            contentType: .commaSeparatedText,
            defaultFilename: "dominios-\(DomainName.split(query).label)"
        ) { _ in }
        .onAppear {
            if router.pendingSearch != nil {
                consumePendingSearch()
            } else if domains.isEmpty {
                fieldFocused = true
            }
        }
        .onChange(of: router.pendingSearch) { consumePendingSearch() }
    }

    private var orderedDomains: [String] {
        guard availableFirst else { return domains }
        func rank(_ domain: String) -> Int {
            switch results[domain]?.status {
            case .available: return 0
            case .likelyAvailable: return 1
            case nil: return 2
            case .unknown: return 3
            case .likelyTaken: return 4
            case .taken: return 5
            }
        }
        return domains.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    private var allTaken: Bool {
        !isChecking && !domains.isEmpty && results.count == domains.count
            && !results.values.contains { $0.status.isAvailable || $0.status == .unknown }
    }

    private var summary: String {
        let free = results.values.filter { $0.status.isAvailable }.count
        return isChecking
            ? "Comprobando \(results.count) de \(domains.count)…"
            : "\(free) de \(domains.count) disponibles"
    }

    private var csv: String {
        CSVExporter.csv(for: domains.compactMap { results[$0] } + ideaResults.values.sorted { $0.domain < $1.domain })
    }

    private func consumePendingSearch() {
        guard let pending = router.pendingSearch else { return }
        router.pendingSearch = nil
        query = pending
        search()
    }

    private func search() {
        let parts = DomainName.split(query)
        guard DomainName.isValidLabel(parts.label) else {
            message = "Escribe un nombre válido: letras, números y guiones (sin espacios al principio o final)."
            return
        }
        var tlds = settings.selectedTLDs
        if let tld = parts.tld {
            tlds.removeAll { $0 == tld }
            tlds.insert(tld, at: 0)
        }
        guard !tlds.isEmpty else {
            message = "Elige al menos una extensión."
            return
        }

        let list = tlds.map { "\(parts.label).\($0)" }
        #if os(iOS)
        fieldFocused = false
        #endif
        message = nil
        domains = list
        results = [:]
        ideaResults = [:]
        alternatives = []
        let seed = parts.tld == nil ? query : parts.label
        ideas = SuggestionEngine.variations(for: seed, limit: 16).filter { $0 != parts.label }

        searchTask?.cancel()
        isChecking = true
        searchTask = Task {
            let all = await AvailabilityService().check(domains: list) { result in
                results[result.domain] = result
            }
            guard !Task.isCancelled else { return }
            isChecking = false
            let free = all.filter { $0.status.isAvailable }.count
            library.recordHistory(query: parts.label, kind: .availability, summary: "\(free) de \(all.count) disponibles")
            all.forEach(library.updateFavoriteStatus)
            if all.allSatisfy({ $0.status == .unknown }), let note = all.first?.note {
                message = note
            }
            if free == 0, !all.contains(where: { $0.status == .unknown }) {
                await findAlternatives(label: parts.label, excluding: tlds)
            }
        }
    }

    /// Cuando todo está ocupado: el mismo nombre en extensiones no marcadas y variaciones en la principal.
    private func findAlternatives(label: String, excluding tlds: [String]) async {
        let otherTLDs = settings.allTLDs.filter { !tlds.contains($0) }.map { "\(label).\($0)" }
        let variations = ideas.prefix(12).map { "\($0).\(ideaTLD)" }
        let candidates = otherTLDs + variations
        guard !candidates.isEmpty else { return }

        isFindingAlternatives = true
        let order = Dictionary(uniqueKeysWithValues: candidates.enumerated().map { ($1, $0) })
        _ = await AvailabilityService(maxConcurrent: 8).check(domains: candidates) { result in
            guard !Task.isCancelled else { return }
            if variations.contains(result.domain) {
                ideaResults[result.domain] = result
            }
            if result.status.isAvailable {
                alternatives.append(result)
                alternatives.sort { (order[$0.domain] ?? 0) < (order[$1.domain] ?? 0) }
            }
        }
        isFindingAlternatives = false
    }

    private func checkIdeas() {
        let list = ideas.map { "\($0).\(ideaTLD)" }
        isCheckingIdeas = true
        Task {
            _ = await AvailabilityService().check(domains: list) { result in
                ideaResults[result.domain] = result
            }
            isCheckingIdeas = false
        }
    }

    private func loadAIIdeas() {
        guard let client = settings.aiClient else { return }
        isLoadingAI = true
        let idea = query
        Task {
            defer { isLoadingAI = false }
            do {
                let names = try await client.suggestions(for: idea)
                var seen = Set<String>()
                ideas = (names + ideas).filter { seen.insert($0).inserted }.prefix(40).map { $0 }
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
