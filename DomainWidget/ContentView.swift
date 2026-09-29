import SwiftUI

/// Consulta rápida de un dominio (ventana de la barra de menú en macOS).
struct ContentView: View {
    @State private var query = ""
    @State private var isLoading = false
    @State private var report: DomainReport?
    @State private var errorMessage: String?
    @State private var lastQuery = ""
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    private let service = DomainLookupService()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isLoading {
                loadingView
            } else if let errorMessage {
                messageView(errorMessage, systemImage: "exclamationmark.triangle")
            } else if let report {
                ScrollView {
                    ReportSectionsView(report: report)
                        .padding(14)
                }
            } else {
                messageView("Escribe un dominio y pulsa Consultar.\nEjemplo: apple.com o wikipedia.org", systemImage: "globe")
            }
        }
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Abrir app completa") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Datos de dominio")
                .font(.headline)
            HStack(spacing: 8) {
                TextField("dominio.com", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .domainInputStyle()
                    .onSubmit { Task { await lookup() } }
                Button("Consultar") {
                    Task { await lookup() }
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(isLoading)
            }
        }
        .padding(14)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Consultando \(lastQuery)…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func lookup() async {
        errorMessage = nil
        lastQuery = query
        isLoading = true
        defer { isLoading = false }
        do {
            report = try await service.lookup(query)
        } catch {
            report = nil
            errorMessage = error.localizedDescription
        }
    }
}
