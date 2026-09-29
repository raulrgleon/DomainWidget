import SwiftUI

/// Consulta rápida desde la barra de menú (macOS): disponibilidad como en Buscar y, si el dominio
/// está registrado, su informe completo.
struct ContentView: View {
    private enum Phase {
        case idle
        case loading(String)
        case failed(String)
        case availability(name: String, tlds: [String])
        case report(DomainReport, DomainAvailability?)
    }

    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    @State private var query = ""
    @State private var phase: Phase = .idle
    @State private var results: [String: DomainAvailability] = [:]
    @State private var isChecking = false
    @State private var task: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Abrir app completa") {
                    openMainWindow()
                }
                .controlSize(.small)
                Spacer()
                Button("Salir") {
                    NSApp.terminate(nil)
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
        }
        #endif
        .onAppear { fieldFocused = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Datos de dominio")
                .font(.headline)
            HStack(spacing: 8) {
                TextField("nombre o dominio.com", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .domainInputStyle()
                    .focused($fieldFocused)
                    .onSubmit(lookup)
                Button("Consultar", action: lookup)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            messageView("Escribe un nombre para ver en qué extensiones está libre, o un dominio para ver si está disponible y sus datos.\nEjemplo: cafeteria o apple.com", systemImage: "globe")
        case .loading(let domain):
            VStack(spacing: 12) {
                ProgressView()
                Text("Consultando \(domain)…")
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            messageView(message, systemImage: "exclamationmark.triangle")
        case .availability(let name, let tlds):
            availabilityView(name: name, tlds: tlds)
        case .report(let report, let availability):
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let availability {
                        HStack {
                            StatusBadge(status: availability.status)
                            Spacer()
                            DomainActionsMenu(domain: report.domain, status: availability.status, expires: availability.expires)
                                .fixedSize()
                        }
                    }
                    ReportSectionsView(report: report)
                }
                .padding(14)
            }
        }
    }

    private func availabilityView(name: String, tlds: [String]) -> some View {
        let label = String(name.split(separator: ".").first ?? "")
        let domains = tlds.map { "\(label).\($0)" }
        return List {
            if name.contains("."), let first = domains.first, let result = results[first], result.status.isAvailable {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("\(first) está libre", systemImage: result.status.systemImage)
                            .font(.headline)
                            .foregroundStyle(result.status.tint)
                        Text(result.status == .available
                             ? "El registro oficial (RDAP) no lo tiene registrado. El precio final lo confirma el registrador."
                             : "Esta extensión no tiene RDAP público; no existe en DNS, así que probablemente está libre.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        RegisterMenu(domain: first)
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                ForEach(domains, id: \.self) { domain in
                    AvailabilityRow(domain: domain, result: results[domain], isPending: isChecking) {
                        query = domain
                        lookup()
                    }
                }
            } header: {
                let free = results.values.filter { $0.status.isAvailable }.count
                Text(isChecking ? "Comprobando…" : "\(free) de \(tlds.count) disponibles")
            } footer: {
                Button("Ver ideas y más opciones en la app") {
                    router.search(label)
                    openMainWindow()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }

    private func messageView(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }

    private func lookup() {
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        task?.cancel()
        results = [:]

        let parts = DomainName.split(input)
        guard DomainName.isValidLabel(parts.label) else {
            phase = .failed(LookupError.invalidDomain.localizedDescription)
            return
        }

        guard let tld = parts.tld, let domain = DomainLookupService.normalizeDomain(input) else {
            checkAvailability(label: parts.label, tlds: settings.selectedTLDs, analyzeIfTaken: nil)
            return
        }

        // Subdominios (www.apple.com): directamente al informe.
        if domain.split(separator: ".").count > 2 {
            showReport(domain, availability: nil)
            return
        }

        let others = settings.selectedTLDs.filter { $0 != tld }
        checkAvailability(label: parts.label, tlds: [tld] + others, analyzeIfTaken: domain)
    }

    /// Comprueba la etiqueta en varias extensiones. Si `analyzeIfTaken` está registrado, muestra su informe.
    private func checkAvailability(label: String, tlds: [String], analyzeIfTaken domain: String?) {
        guard !tlds.isEmpty else {
            phase = .failed("Elige al menos una extensión en Ajustes.")
            return
        }
        let domains = tlds.map { "\(label).\($0)" }
        phase = .loading(domain ?? label)
        isChecking = true
        task = Task {
            if let domain {
                let primary = await AvailabilityService().check(domain)
                guard !Task.isCancelled else { return }
                results[domain] = primary
                if !primary.status.isAvailable && primary.status != .unknown {
                    isChecking = false
                    showReport(domain, availability: primary)
                    return
                }
            }
            phase = .availability(name: domain ?? label, tlds: tlds)
            let all = await AvailabilityService().check(domains: domains.filter { results[$0] == nil }) { result in
                results[result.domain] = result
            }
            guard !Task.isCancelled else { return }
            isChecking = false
            let free = (all + (domain.flatMap { results[$0] }.map { [$0] } ?? [])).filter { $0.status.isAvailable }.count
            library.recordHistory(query: label, kind: .availability, summary: "\(free) de \(tlds.count) disponibles")
        }
    }

    private func showReport(_ domain: String, availability: DomainAvailability?) {
        phase = .loading(domain)
        task = Task {
            do {
                let report = try await DomainLookupService().lookup(domain)
                guard !Task.isCancelled else { return }
                phase = .report(report, availability)
                library.recordHistory(query: domain, kind: .analysis, summary: report.registration?.registrar ?? "Analizado")
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func openMainWindow() {
        #if os(macOS)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        #endif
    }
}
