import SwiftUI

struct ContentView: View {
    @State private var query = ""
    @State private var isLoading = false
    @State private var report: DomainReport?
    @State private var errorMessage: String?
    @State private var lastQuery = ""

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
                resultsView(report)
            } else {
                messageView("Escribe un dominio y pulsa Consultar.\nEjemplo: apple.com o wikipedia.org", systemImage: "globe")
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("También aparece en la barra de menú, junto al reloj.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Datos de dominio")
                .font(.headline)
            HStack(spacing: 8) {
                TextField("dominio.com", text: $query)
                    .textFieldStyle(.roundedBorder)
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

    private func resultsView(_ report: DomainReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(report.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "info.circle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }

                section("General", icon: "link") {
                    row("Dominio", report.domain)
                    if let http = report.http {
                        row("HTTP", "\(http.statusCode)")
                        row("URL final", http.finalURL)
                        if let server = http.server { row("Servidor", server) }
                    } else {
                        row("HTTP", "Sin respuesta HTTPS")
                    }
                    row("Consultado", report.queriedAt.formatted(date: .abbreviated, time: .standard))
                }

                if let geo = report.geo {
                    section("Ubicación del servidor", icon: "mappin.and.ellipse") {
                        row("IP", geo.ip)
                        row("País", geo.country ?? "—")
                        row("Ciudad", [geo.city, geo.region].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
                        row("Organización", geo.org ?? "—")
                        if let asn = geo.asn { row("ASN", asn) }
                    }
                }

                section("DNS", icon: "list.bullet.rectangle") {
                    row("A", joined(report.ipv4))
                    row("AAAA", joined(report.ipv6))
                    row("CNAME", joined(report.cname))
                    row("MX", joined(report.mx))
                    row("NS", joined(report.nameservers))
                    row("TXT", joined(report.txt))
                }

                if let ssl = report.ssl {
                    section("Certificado SSL", icon: "lock.shield") {
                        row("Asunto", ssl.subject)
                        row("Emisor", ssl.issuer)
                        row("Válido desde", format(ssl.validFrom))
                        row("Válido hasta", format(ssl.validUntil))
                        if ssl.isExpired {
                            row("Estado", "Caducado")
                        } else if let days = ssl.daysRemaining {
                            row("Estado", "Vigente · \(days) días")
                        }
                    }
                } else {
                    section("Certificado SSL", icon: "lock.slash") {
                        row("Estado", "No se pudo leer el certificado")
                    }
                }

                if let registration = report.registration {
                    section("Registro (\(registration.source))", icon: "building.columns") {
                        row("Registrador", registration.registrar ?? "—")
                        row("Creado", prettyDate(registration.created))
                        row("Caduca", prettyDate(registration.expires))
                        row("Actualizado", prettyDate(registration.updated))
                        if !registration.statuses.isEmpty {
                            row("Estado", registration.statuses.joined(separator: ", "))
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func section(_ title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copiar")
            .disabled(value.isEmpty)
        }
        .font(.caption)
    }

    private func joined(_ values: [String]) -> String {
        values.isEmpty ? "" : values.joined(separator: "\n")
    }

    private func format(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func prettyDate(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "—" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) ?? ISO8601DateFormatter().date(from: value) {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return value
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
