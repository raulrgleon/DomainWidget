import SwiftUI

/// Secciones del informe de un dominio, compartidas entre la barra de menú y la app completa.
struct ReportSectionsView: View {
    let report: DomainReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(report.warnings, id: \.self) { warning in
                Label(warning, systemImage: "info.circle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            ReportSection(title: "General", icon: "link") {
                ReportRow(label: "Dominio", value: report.domain)
                if let http = report.http {
                    ReportRow(label: "HTTP", value: "\(http.statusCode)")
                    ReportRow(label: "URL final", value: http.finalURL)
                    if let server = http.server { ReportRow(label: "Servidor", value: server) }
                } else {
                    ReportRow(label: "HTTP", value: "Sin respuesta HTTPS")
                }
                ReportRow(label: "Consultado", value: report.queriedAt.formatted(date: .abbreviated, time: .standard))
            }

            if let geo = report.geo {
                ReportSection(title: "Ubicación del servidor", icon: "mappin.and.ellipse") {
                    ReportRow(label: "IP", value: geo.ip)
                    ReportRow(label: "País", value: geo.country ?? "")
                    ReportRow(label: "Ciudad", value: [geo.city, geo.region].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
                    ReportRow(label: "Organización", value: geo.org ?? "")
                    if let asn = geo.asn { ReportRow(label: "ASN", value: asn) }
                }
            }

            ReportSection(title: "DNS", icon: "list.bullet.rectangle") {
                ReportRow(label: "A", value: report.ipv4.joined(separator: "\n"))
                ReportRow(label: "AAAA", value: report.ipv6.joined(separator: "\n"))
                ReportRow(label: "CNAME", value: report.cname.joined(separator: "\n"))
                ReportRow(label: "MX", value: report.mx.joined(separator: "\n"))
                ReportRow(label: "NS", value: report.nameservers.joined(separator: "\n"))
                ReportRow(label: "TXT", value: report.txt.joined(separator: "\n"))
            }

            if let ssl = report.ssl {
                ReportSection(title: "Certificado SSL", icon: ssl.isTrusted ? "lock.shield" : "exclamationmark.shield") {
                    ReportRow(label: "Asunto", value: ssl.subject)
                    ReportRow(label: "Emisor", value: ssl.issuer)
                    ReportRow(label: "Válido desde", value: ssl.validFrom.map(Self.dateOnly) ?? "")
                    ReportRow(label: "Válido hasta", value: ssl.validUntil.map(Self.dateOnly) ?? "")
                    ReportRow(label: "Estado", value: sslStatus(ssl))
                }
            } else {
                ReportSection(title: "Certificado SSL", icon: "lock.slash") {
                    ReportRow(label: "Estado", value: "No se pudo leer el certificado")
                }
            }

            if let registration = report.registration {
                ReportSection(title: "Registro (\(registration.source))", icon: "building.columns") {
                    ReportRow(label: "Registrador", value: registration.registrar ?? "")
                    ReportRow(label: "Creado", value: Self.prettyDate(registration.created))
                    ReportRow(label: "Caduca", value: Self.prettyDate(registration.expires))
                    ReportRow(label: "Actualizado", value: Self.prettyDate(registration.updated))
                    if !registration.statuses.isEmpty {
                        ReportRow(label: "Estado", value: registration.statuses.joined(separator: ", "))
                    }
                }
            }
        }
    }

    private func sslStatus(_ ssl: SSLInfo) -> String {
        if ssl.isExpired { return "Caducado" }
        var parts: [String] = [ssl.isTrusted ? "De confianza" : "No es de confianza"]
        if let days = ssl.daysRemaining { parts.append("\(days) días restantes") }
        return parts.joined(separator: " · ")
    }

    static func dateOnly(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    static func prettyDate(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        return DateParsing.iso8601(value).map(dateOnly) ?? value
    }
}

struct ReportSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ReportRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Clipboard.copy(value)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copiar")
            .disabled(value.isEmpty)
        }
        .font(.caption)
    }
}
