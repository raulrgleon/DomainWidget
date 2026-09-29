import Foundation

enum AvailabilityStatus: String, Codable, CaseIterable {
    case available
    case taken
    case likelyAvailable
    case likelyTaken
    case unknown

    var label: String {
        switch self {
        case .available: return "Disponible"
        case .taken: return "Ocupado"
        case .likelyAvailable: return "Probablemente libre"
        case .likelyTaken: return "Probablemente ocupado"
        case .unknown: return "Desconocido"
        }
    }

    var systemImage: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .taken: return "xmark.circle.fill"
        case .likelyAvailable: return "checkmark.circle"
        case .likelyTaken: return "xmark.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    var isAvailable: Bool { self == .available || self == .likelyAvailable }
}

struct DomainAvailability: Identifiable, Hashable, Codable {
    var id: String { domain }
    let domain: String
    let status: AvailabilityStatus
    let source: String
    let expires: Date?
    let registrar: String?
    let note: String?
    let checkedAt: Date
}

enum DomainName {
    static let defaultTLDs = ["com", "net", "org", "io", "ai", "app", "dev", "co", "bio", "me", "xyz", "es", "mx"]

    /// Normaliza un nombre base: minúsculas, sin espacios ni caracteres no válidos.
    static func sanitizeLabel(_ input: String) -> String {
        let lowered = input.lowercased()
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let allowed = lowered.unicodeScalars.filter {
            CharacterSet.lowercaseLetters.contains($0) && $0.isASCII
                || CharacterSet.decimalDigits.contains($0) && $0.isASCII
                || $0 == "-"
        }
        var label = String(String.UnicodeScalarView(allowed))
        while label.hasPrefix("-") { label.removeFirst() }
        while label.hasSuffix("-") { label.removeLast() }
        return String(label.prefix(63))
    }

    static func isValidLabel(_ label: String) -> Bool {
        !label.isEmpty && label.count <= 63
            && label.range(of: #"^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"#, options: .regularExpression) != nil
    }

    /// Separa "miweb.com" en ("miweb", "com"). Si no hay punto, devuelve tld nil.
    static func split(_ input: String) -> (label: String, tld: String?) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let normalized = DomainLookupService.normalizeDomain(trimmed), let dot = normalized.firstIndex(of: ".") {
            return (String(normalized[..<dot]), String(normalized[normalized.index(after: dot)...]))
        }
        return (sanitizeLabel(trimmed), nil)
    }
}

/// Comprueba la disponibilidad de muchos dominios en paralelo con RDAP y, si el TLD no tiene RDAP, con DNS.
struct AvailabilityService {
    var maxConcurrent = 6
    private let dns = DNSClient()

    func check(domains: [String], useCache: Bool = true, onResult: (@MainActor (DomainAvailability) -> Void)? = nil) async -> [DomainAvailability] {
        var results: [DomainAvailability] = []
        await withTaskGroup(of: DomainAvailability.self) { group in
            var iterator = domains.makeIterator()
            for _ in 0..<min(maxConcurrent, domains.count) {
                if let domain = iterator.next() {
                    group.addTask { await check(domain, useCache: useCache) }
                }
            }
            while let result = await group.next() {
                results.append(result)
                if let onResult { await onResult(result) }
                if let domain = iterator.next() {
                    group.addTask { await check(domain, useCache: useCache) }
                }
            }
        }
        let order = Dictionary(uniqueKeysWithValues: domains.enumerated().map { ($1, $0) })
        return results.sorted { (order[$0.domain] ?? 0) < (order[$1.domain] ?? 0) }
    }

    func check(_ domain: String, useCache: Bool = true) async -> DomainAvailability {
        var rdapError: Error?
        do {
            switch try await RDAPClient.shared.lookup(domain, useCache: useCache) {
            case .registered(let info):
                return DomainAvailability(
                    domain: domain, status: .taken, source: "RDAP",
                    expires: info.expiryDate, registrar: info.registrar,
                    note: info.statuses.isEmpty ? nil : info.statuses.joined(separator: ", "),
                    checkedAt: Date()
                )
            case .notFound:
                return DomainAvailability(
                    domain: domain, status: .available, source: "RDAP",
                    expires: nil, registrar: nil,
                    note: "El registrador confirma el precio final (algunos nombres son premium).",
                    checkedAt: Date()
                )
            case .unsupported:
                break
            }
        } catch NetworkError.offline {
            return failure(domain, NetworkError.offline)
        } catch {
            rdapError = error
        }
        return await dnsFallback(domain, rdapError: rdapError)
    }

    private func dnsFallback(_ domain: String, rdapError: Error?) async -> DomainAvailability {
        let prefix = rdapError == nil ? "Este TLD no tiene RDAP público" : "RDAP falló"
        do {
            let result = try await dns.query(domain, .ns)
            if result.isNXDomain {
                return DomainAvailability(
                    domain: domain, status: .likelyAvailable, source: "DNS",
                    expires: nil, registrar: nil,
                    note: "\(prefix); no existe en DNS. Confírmalo en un registrador.",
                    checkedAt: Date()
                )
            }
            return DomainAvailability(
                domain: domain, status: .likelyTaken, source: "DNS",
                expires: nil, registrar: nil,
                note: "\(prefix); el dominio existe en DNS.",
                checkedAt: Date()
            )
        } catch {
            return failure(domain, rdapError ?? error)
        }
    }

    private func failure(_ domain: String, _ error: Error) -> DomainAvailability {
        DomainAvailability(
            domain: domain, status: .unknown, source: "—",
            expires: nil, registrar: nil,
            note: error.localizedDescription,
            checkedAt: Date()
        )
    }
}
