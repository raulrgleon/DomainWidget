import SwiftUI

struct AnalyzeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library

    @State private var query = ""
    @State private var error: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    TextField("dominio.com o URL", text: $query)
                        .domainInputStyle()
                        .focused($fieldFocused)
                        .onSubmit(analyze)
                    Button("Analizar", action: analyze)
                        .buttonStyle(.borderedProminent)
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("DNS, certificado SSL, servidor, ubicación de la IP y datos de registro de un dominio existente.")
            }

            let recent = library.history.filter { $0.kind == .analysis }.prefix(15)
            if !recent.isEmpty {
                Section("Recientes") {
                    ForEach(Array(recent)) { entry in
                        Button {
                            router.analyze(entry.query)
                        } label: {
                            Label(entry.query, systemImage: "clock")
                        }
                    }
                }
            }
        }
        .navigationTitle("Analizar dominio")
        .onAppear { fieldFocused = true }
    }

    private func analyze() {
        guard let domain = DomainLookupService.normalizeDomain(query) else {
            error = LookupError.invalidDomain.localizedDescription
            return
        }
        error = nil
        router.analyze(domain)
    }
}

/// Carga y muestra el informe completo de un dominio.
struct DomainReportScreen: View {
    let domain: String

    @Environment(LibraryStore.self) private var library
    @Environment(NetworkMonitor.self) private var network
    @State private var report: DomainReport?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            if let report {
                ReportSectionsView(report: report)
                    .padding()
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("No se pudo analizar", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Reintentar") { Task { await load() } }
                }
                .padding(.top, 40)
            } else {
                ProgressView("Analizando \(domain)…")
                    .padding(.top, 60)
            }
        }
        .navigationTitle(domain)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await load() }
                } label: {
                    Label("Actualizar", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(isLoading)
            }
            ToolbarItem(placement: .primaryAction) {
                DomainActionsMenu(domain: domain, status: nil, expires: report?.registration?.expiryDate)
            }
        }
        .task(id: domain) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard network.isOnline else {
            errorMessage = NetworkError.offline.localizedDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let result = try await DomainLookupService().lookup(domain)
            report = result
            library.recordHistory(query: domain, kind: .analysis, summary: result.registration?.registrar ?? "Analizado")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
