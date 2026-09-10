import Foundation
import Security

struct DomainLookupService {
    func lookup(_ rawInput: String) async throws -> DomainReport {
        guard let domain = Self.normalizeDomain(rawInput) else {
            throw rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? LookupError.emptyInput
                : LookupError.invalidDomain
        }

        var report = DomainReport(domain: domain, queriedAt: Date())

        async let ipv4 = dig(domain, type: "A")
        async let ipv6 = dig(domain, type: "AAAA")
        async let mx = dig(domain, type: "MX")
        async let ns = dig(domain, type: "NS")
        async let txt = dig(domain, type: "TXT")
        async let cname = dig(domain, type: "CNAME")
        async let http = fetchHTTP(domain)
        async let ssl = fetchSSL(domain)
        async let registration = fetchRegistration(domain)

        report.ipv4 = await ipv4
        report.ipv6 = await ipv6
        report.mx = await mx
        report.nameservers = await ns
        report.txt = await txt
        report.cname = await cname
        report.http = await http
        report.ssl = await ssl
        report.registration = await registration

        if let ip = report.ipv4.first {
            report.geo = await fetchGeo(ip: ip)
        }

        if report.ipv4.isEmpty && report.ipv6.isEmpty && report.nameservers.isEmpty {
            report.warnings.append("No se encontraron registros DNS. El dominio podría no existir o no estar delegado.")
        }

        return report
    }

    static func normalizeDomain(_ input: String) -> String? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        value = value.replacingOccurrences(of: " ", with: "")
        if !value.contains("://") {
            value = "https://\(value)"
        }

        guard let url = URL(string: value), let host = url.host, !host.isEmpty else {
            return nil
        }

        let cleaned = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard cleaned.contains("."), cleaned.range(of: #"^[a-z0-9.-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return cleaned
    }

    private func dig(_ domain: String, type: String) async -> [String] {
        let output = await run("/usr/bin/dig", ["+short", "+time=3", "+tries=1", type, domain])
        return output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.lowercased().contains("timed out") }
            .map { line in
                var value = String(line)
                if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                return value.replacingOccurrences(of: "\" \"", with: " ")
            }
    }

    private func fetchHTTP(_ domain: String) async -> HTTPInfo? {
        guard let url = URL(string: "https://\(domain)/") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        request.setValue("DomainWidget/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            return HTTPInfo(
                statusCode: http.statusCode,
                finalURL: http.url?.absoluteString ?? url.absoluteString,
                server: http.value(forHTTPHeaderField: "Server"),
                contentType: http.value(forHTTPHeaderField: "Content-Type")
            )
        } catch {
            return await fetchHTTPGet(domain)
        }
    }

    private func fetchHTTPGet(_ domain: String) async -> HTTPInfo? {
        guard let url = URL(string: "https://\(domain)/") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("DomainWidget/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            return HTTPInfo(
                statusCode: http.statusCode,
                finalURL: http.url?.absoluteString ?? url.absoluteString,
                server: http.value(forHTTPHeaderField: "Server"),
                contentType: http.value(forHTTPHeaderField: "Content-Type")
            )
        } catch {
            return nil
        }
    }

    private func fetchSSL(_ domain: String) async -> SSLInfo? {
        await withCheckedContinuation { continuation in
            let delegate = SSLCaptureDelegate()
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 8
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            guard let url = URL(string: "https://\(domain)/") else {
                continuation.resume(returning: nil)
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            let task = session.dataTask(with: request) { _, _, _ in
                continuation.resume(returning: delegate.info)
                session.invalidateAndCancel()
            }
            task.resume()
        }
    }

    private func fetchRegistration(_ domain: String) async -> RegistrationInfo? {
        if let rdap = await fetchRDAP(domain) {
            return rdap
        }
        return await fetchWhois(domain)
    }

    private func fetchRDAP(_ domain: String) async -> RegistrationInfo? {
        guard let url = URL(string: "https://rdap.org/domain/\(domain)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/rdap+json, application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return parseRDAP(json)
        } catch {
            return nil
        }
    }

    private func parseRDAP(_ json: [String: Any]) -> RegistrationInfo {
        let events = json["events"] as? [[String: Any]] ?? []
        func event(_ action: String) -> String? {
            events.first(where: { ($0["eventAction"] as? String)?.lowercased() == action })?["eventDate"] as? String
        }

        var registrar: String?
        if let entities = json["entities"] as? [[String: Any]] {
            for entity in entities {
                let roles = (entity["roles"] as? [String] ?? []).map { $0.lowercased() }
                if roles.contains("registrar") {
                    registrar = vcardFN(entity) ?? entity["handle"] as? String
                    break
                }
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

    private func vcardFN(_ entity: [String: Any]) -> String? {
        guard let vcard = entity["vcardArray"] as? [Any],
              vcard.count >= 2,
              let fields = vcard[1] as? [[Any]] else { return nil }
        for field in fields {
            guard field.count >= 4, let name = field[0] as? String, name.lowercased() == "fn" else { continue }
            return field[3] as? String
        }
        return nil
    }

    private func fetchWhois(_ domain: String) async -> RegistrationInfo? {
        let output = await run("/usr/bin/whois", [domain])
        guard !output.isEmpty else { return nil }

        func firstMatch(_ keys: [String]) -> String? {
            for line in output.split(whereSeparator: \.isNewline) {
                let text = String(line)
                for key in keys {
                    if text.lowercased().hasPrefix(key.lowercased()) {
                        let value = text.split(separator: ":", maxSplits: 1).dropFirst().first?
                            .trimmingCharacters(in: .whitespaces)
                        if let value, !value.isEmpty { return value }
                    }
                }
            }
            return nil
        }

        return RegistrationInfo(
            registrar: firstMatch(["Registrar:", "registrar:"]),
            created: firstMatch(["Creation Date:", "created:", "Created On:"]),
            expires: firstMatch(["Registry Expiry Date:", "Expiry Date:", "expires:"]),
            updated: firstMatch(["Updated Date:", "last-modified:"]),
            statuses: [],
            rdapNameservers: [],
            source: "WHOIS"
        )
    }

    private func fetchGeo(ip: String) async -> GeoInfo? {
        guard let url = URL(string: "https://ipwho.is/\(ip)") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["success"] as? Bool != false else { return nil }
            let connection = json["connection"] as? [String: Any]
            return GeoInfo(
                ip: ip,
                city: json["city"] as? String,
                region: json["region"] as? String,
                country: json["country"] as? String,
                org: connection?["org"] as? String ?? json["org"] as? String,
                asn: (connection?["asn"] as? Int).map(String.init) ?? json["asn"] as? String
            )
        } catch {
            return nil
        }
    }

    private func run(_ launchPath: String, _ arguments: [String]) async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            } catch {
                continuation.resume(returning: "")
            }
        }
    }
}

private final class SSLCaptureDelegate: NSObject, URLSessionDelegate {
    var info: SSLInfo?

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        defer { completionHandler(.performDefaultHandling, nil) }
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else { return }

        let cert: SecCertificate?
        if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] {
            cert = chain.first
        } else {
            cert = nil
        }
        guard let cert else { return }

        var error: Unmanaged<CFError>?
        guard let values = SecCertificateCopyValues(cert, nil, &error) as? [CFString: Any] else { return }

        func stringValue(_ oid: CFString) -> String? {
            guard let dict = values[oid] as? [CFString: Any] else { return nil }
            if let label = dict[kSecPropertyKeyLabel] as? String,
               let value = dict[kSecPropertyKeyValue] {
                return "\(value)".isEmpty ? label : "\(value)"
            }
            return dict[kSecPropertyKeyValue].map { "\($0)" }
        }

        func nestedName(_ oid: CFString) -> String? {
            guard let dict = values[oid] as? [CFString: Any],
                  let items = dict[kSecPropertyKeyValue] as? [[CFString: Any]] else {
                return stringValue(oid)
            }
            let parts = items.compactMap { item -> String? in
                guard let label = item[kSecPropertyKeyLabel] as? String,
                      let value = item[kSecPropertyKeyValue] else { return nil }
                return "\(label)=\(value)"
            }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }

        let from = dateValue(values[kSecOIDX509V1ValidityNotBefore] as? [CFString: Any])
        let until = dateValue(values[kSecOIDX509V1ValidityNotAfter] as? [CFString: Any])
        let remaining: Int?
        let expired: Bool
        if let until {
            remaining = Calendar.current.dateComponents([.day], from: Date(), to: until).day
            expired = until < Date()
        } else {
            remaining = nil
            expired = false
        }

        info = SSLInfo(
            subject: nestedName(kSecOIDX509V1SubjectName) ?? "Desconocido",
            issuer: nestedName(kSecOIDX509V1IssuerName) ?? "Desconocido",
            validFrom: from,
            validUntil: until,
            isExpired: expired,
            daysRemaining: remaining
        )
    }

    private func dateValue(_ dict: [CFString: Any]?) -> Date? {
        guard let value = dict?[kSecPropertyKeyValue] else { return nil }
        if let date = value as? Date { return date }
        if let number = value as? TimeInterval {
            return Date(timeIntervalSinceReferenceDate: number)
        }
        return nil
    }
}
