import SwiftUI
import UniformTypeIdentifiers

/// Comprobación masiva desde texto pegado o un archivo CSV/TXT, con exportación.
struct BulkView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "Todos"
        case available = "Libres"
        case taken = "Ocupados"

        var id: String { rawValue }
    }

    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library

    @State private var text = ""
    @State private var domains: [String] = []
    @State private var results: [String: DomainAvailability] = [:]
    @State private var isChecking = false
    @State private var filter: Filter = .all
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var message: String?
    @State private var task: Task<Void, Never>?

    private var parsed: [String] { BulkParser.parse(text, defaultTLD: settings.bulkDefaultTLD) }

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .frame(minHeight: 120)
                    .domainInputStyle()
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("cafeteria\nmitienda.io\nraul.dev, raul.app")
                                .font(.body.monospaced())
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            if let pasted = Clipboard.string() { text = pasted }
                        } label: {
                            Label("Pegar", systemImage: "doc.on.clipboard")
                        }
                        Button {
                            text = "cafeteria\ncafeteriaonline\nmicafe.io\nmicafe.app\ncafe-rapido.com"
                        } label: {
                            Label("Ejemplo", systemImage: "wand.and.stars")
                        }
                        if !library.favorites.isEmpty {
                            Button {
                                text = library.favorites.map(\.domain).joined(separator: "\n")
                            } label: {
                                Label("Favoritos", systemImage: "star")
                            }
                        }
                        if !text.isEmpty {
                            Button(role: .destructive) {
                                text = ""
                                domains = []
                                results = [:]
                            } label: {
                                Label("Limpiar", systemImage: "xmark.circle")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Picker("Extensión si falta", selection: $settings.bulkDefaultTLD) {
                    ForEach(settings.allTLDs, id: \.self) { Text(".\($0)").tag($0) }
                }
                HStack {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Importar CSV/TXT", systemImage: "doc.badge.plus")
                    }
                    Spacer()
                    if isChecking {
                        Button("Detener", role: .cancel) {
                            task?.cancel()
                            isChecking = false
                        }
                    } else {
                        Button("Comprobar \(parsed.count)", action: run)
                            .buttonStyle(.borderedProminent)
                            .disabled(parsed.isEmpty)
                    }
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text("Pega dominios o nombres")
            } footer: {
                Text("Uno por línea o separados por comas. En un CSV se usa cada celda que parezca un dominio. Máximo 500.")
            }

            if domains.isEmpty {
                Section("Cómo funciona") {
                    Label("Pega una lista, usa el ejemplo o importa un CSV con tus dominios.", systemImage: "1.circle.fill")
                    Label("Los nombres sin extensión usan la que elijas arriba (.\(settings.bulkDefaultTLD)).", systemImage: "2.circle.fill")
                    Label("Comprobamos hasta 8 a la vez en el registro oficial (RDAP).", systemImage: "3.circle.fill")
                    Label("Filtra los libres y exporta el resultado a CSV o compártelo.", systemImage: "4.circle.fill")
                }
                .font(.callout)
            } else {
                Section {
                    Picker("Filtro", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if isChecking {
                        ProgressView(value: Double(results.count), total: Double(domains.count))
                    }
                    ForEach(filtered, id: \.self) { domain in
                        AvailabilityRow(domain: domain, result: results[domain], isPending: isChecking)
                    }
                } header: {
                    let free = results.values.filter { $0.status.isAvailable }.count
                    Text("\(free) libres · \(results.count - free) ocupados o desconocidos · \(results.count)/\(domains.count)")
                }
            }
        }
        .navigationTitle("Comprobación masiva")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
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
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
            importFile(result)
        }
        .fileExporter(isPresented: $showExporter, document: CSVDocument(text: csv), contentType: .commaSeparatedText, defaultFilename: "dominios-masivo") { _ in }
    }

    private var filtered: [String] {
        switch filter {
        case .all: return domains
        case .available: return domains.filter { results[$0]?.status.isAvailable == true }
        case .taken: return domains.filter { results[$0].map { !$0.status.isAvailable } ?? false }
        }
    }

    private var csv: String {
        CSVExporter.csv(for: domains.compactMap { results[$0] })
    }

    private func run() {
        let list = parsed
        guard !list.isEmpty else { return }
        domains = list
        results = [:]
        message = nil
        isChecking = true
        task?.cancel()
        task = Task {
            let all = await AvailabilityService(maxConcurrent: 8).check(domains: list) { result in
                results[result.domain] = result
            }
            guard !Task.isCancelled else { return }
            isChecking = false
            let free = all.filter { $0.status.isAvailable }.count
            library.recordHistory(query: "\(list.count) dominios", kind: .bulk, summary: "\(free) libres")
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let contents = try? String(contentsOf: url, encoding: .utf8) {
                text = contents
                message = "\(BulkParser.parse(contents, defaultTLD: settings.bulkDefaultTLD).count) dominios importados."
            } else {
                message = "No se pudo leer el archivo (usa texto UTF-8)."
            }
        case .failure(let error):
            message = error.localizedDescription
        }
    }
}
