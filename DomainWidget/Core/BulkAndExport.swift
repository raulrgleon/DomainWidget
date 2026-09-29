import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum BulkParser {
    /// Acepta dominios separados por líneas, comas, punto y coma o espacios; ignora líneas con #.
    /// En un CSV usa la primera columna. Los nombres sin TLD reciben `defaultTLD`.
    static func parse(_ text: String, defaultTLD: String = "com", limit: Int = 500) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let tokens = trimmed.components(separatedBy: CharacterSet(charactersIn: ",; \t"))
            for token in tokens {
                let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                guard !cleaned.isEmpty, cleaned.lowercased() != "domain", cleaned.lowercased() != "dominio" else { continue }
                let parts = DomainName.split(cleaned)
                guard DomainName.isValidLabel(parts.label) else { continue }
                let domain = "\(parts.label).\(parts.tld ?? defaultTLD)"
                if seen.insert(domain).inserted {
                    result.append(domain)
                }
                if result.count >= limit { return result }
            }
        }
        return result
    }
}

enum CSVExporter {
    static func csv(for results: [DomainAvailability]) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["dominio,estado,fuente,caduca,registrador,nota,consultado"]
        for item in results {
            lines.append([
                item.domain,
                item.status.label,
                item.source,
                item.expires.map { formatter.string(from: $0) } ?? "",
                item.registrar ?? "",
                item.note ?? "",
                formatter.string(from: item.checkedAt)
            ].map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
