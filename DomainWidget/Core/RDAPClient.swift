import Foundation

enum RDAPResult {
    case registered(RegistrationInfo)
    case notFound
    case unsupported
}

/// Cliente RDAP con bootstrap de IANA, caché en memoria y límite de ritmo por servidor.
actor RDAPClient {
    static let shared = RDAPClient()

    private static let bootstrapURL = URL(string: "https://data.iana.org/rdap/dns.json")!
    private static let bootstrapMaxAge: TimeInterval = 60 * 60 * 24
    private static let resultTTL: TimeInterval = 60 * 10
    private static let minInterval: TimeInterval = 0.35

    private var servers: [String: URL] = [:]
    private var bootstrapLoadedAt: Date?
    private var bootstrapTask: Task<Void, Error>?
    private var cache: [String: (date: Date, result: RDAPResult)] = [:]
    private var nextAllowed: [String: Date] = [:]

    func lookup(_ domain: String, useCache: Bool = true) async throws -> RDAPResult {
        let domain = domain.lowercased()
        if useCache, let cached = cache[domain], Date().timeIntervalSince(cached.date) < Self.resultTTL {
            return cached.result
        }

        try await loadBootstrapIfNeeded()
        guard let tld = domain.split(separator: ".").last.map(String.init),
              let base = servers[tld] else {
            return .unsupported
        }

        let url = base.appendingPathComponent("domain").appendingPathComponent(domain)
        let result = try await fetch(url, attempt: 0)
        cache[domain] = (Date(), result)
        return result
    }

    func supports(tld: String) async -> Bool {
        try? await loadBootstrapIfNeeded()
        return servers[tld.lowercased()] != nil
    }

    private func fetch(_ url: URL, attempt: Int) async throws -> RDAPResult {
        let host = url.host ?? "rdap"
        await throttle(host: host)

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/rdap+json, application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await HTTPClient.data(for: request)
        switch response.statusCode {
        case 200...299:
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NetworkError.invalidResponse
            }
            return .registered(Self.parse(json))
        case 404:
            return .notFound
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 2
            nextAllowed[host] = Date().addingTimeInterval(min(retryAfter, 10))
            guard attempt < 2 else { throw NetworkError.rateLimited(host: host) }
            return try await fetch(url, attempt: attempt + 1)
        default:
            throw NetworkError.server(status: response.statusCode)
        }
    }

    private func throttle(host: String) async {
        let now = Date()
        let slot = max(now, nextAllowed[host] ?? now)
        nextAllowed[host] = slot.addingTimeInterval(Self.minInterval)
        let wait = slot.timeIntervalSince(now)
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }

    private func loadBootstrapIfNeeded() async throws {
        if let loadedAt = bootstrapLoadedAt, Date().timeIntervalSince(loadedAt) < Self.bootstrapMaxAge {
            return
        }
        if let task = bootstrapTask {
            return try await task.value
        }
        let task = Task { try await self.loadBootstrap() }
        bootstrapTask = task
        defer { bootstrapTask = nil }
        try await task.value
    }

    private func loadBootstrap() async throws {
        let cacheFile = Self.cacheFileURL
        if let attributes = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
           let modified = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < Self.bootstrapMaxAge,
           let data = try? Data(contentsOf: cacheFile),
           applyBootstrap(data) {
            bootstrapLoadedAt = modified
            return
        }

        do {
            let (data, response) = try await HTTPClient.data(for: URLRequest(url: Self.bootstrapURL))
            guard (200...299).contains(response.statusCode), applyBootstrap(data) else {
                throw NetworkError.server(status: response.statusCode)
            }
            try? data.write(to: cacheFile, options: .atomic)
            bootstrapLoadedAt = Date()
        } catch {
            if let data = try? Data(contentsOf: cacheFile), applyBootstrap(data) {
                bootstrapLoadedAt = Date()
                return
            }
            throw error
        }
    }

    private func applyBootstrap(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let services = json["services"] as? [[Any]] else { return false }

        var map: [String: URL] = [:]
        for service in services where service.count >= 2 {
            guard let tlds = service[0] as? [String], let urls = service[1] as? [String] else { continue }
            let preferred = urls.first(where: { $0.hasPrefix("https://") })
            guard let preferred, let url = URL(string: preferred) else { continue }
            for tld in tlds {
                map[tld.lowercased()] = url
            }
        }
        guard !map.isEmpty else { return false }
        servers = map
        return true
    }

    private static var cacheFileURL: URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("rdap-bootstrap-dns.json")
    }

    static func parse(_ json: [String: Any]) -> RegistrationInfo {
        let events = json["events"] as? [[String: Any]] ?? []
        func event(_ action: String) -> String? {
            events.first(where: { ($0["eventAction"] as? String)?.lowercased() == action })?["eventDate"] as? String
        }

        var registrar: String?
        for entity in json["entities"] as? [[String: Any]] ?? [] {
            let roles = (entity["roles"] as? [String] ?? []).map { $0.lowercased() }
            if roles.contains("registrar") {
                registrar = vcardFN(entity) ?? entity["handle"] as? String
                break
            }
        }

        let nameservers = (json["nameservers"] as? [[String: Any]] ?? [])
            .compactMap { $0["ldhName"] as? String }
        let statuses = (json["status"] as? [String] ?? []).map { $0.replacingOccurrences(of: "-", with: " ") }

        return RegistrationInfo(
            registrar: registrar,
            created: event("registration"),
            expires: event("expiration"),
            updated: event("last changed") ?? event("last update of rdap database"),
            statuses: statuses,
            rdapNameservers: nameservers,
            source: "RDAP"
        )
    }

    private static func vcardFN(_ entity: [String: Any]) -> String? {
        guard let vcard = entity["vcardArray"] as? [Any],
              vcard.count >= 2,
              let fields = vcard[1] as? [[Any]] else { return nil }
        for field in fields {
            guard field.count >= 4, let name = field[0] as? String, name.lowercased() == "fn" else { continue }
            return field[3] as? String
        }
        return nil
    }
}

extension RegistrationInfo {
    var expiryDate: Date? { DateParsing.iso8601(expires) }
}

enum DateParsing {
    static func iso8601(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
