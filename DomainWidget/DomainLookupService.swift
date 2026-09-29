import Foundation
import Security

struct DomainLookupService {
    private let dns = DNSClient()

    func lookup(_ rawInput: String) async throws -> DomainReport {
        guard let domain = Self.normalizeDomain(rawInput) else {
            throw rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? LookupError.emptyInput
                : LookupError.invalidDomain
        }

        var report = DomainReport(domain: domain, queriedAt: Date())

        async let ipv4 = dns.records(domain, .a)
        async let ipv6 = dns.records(domain, .aaaa)
        async let mx = dns.records(domain, .mx)
        async let ns = dns.records(domain, .ns)
        async let txt = dns.records(domain, .txt)
        async let cname = dns.records(domain, .cname)
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
            if report.registration == nil {
                report.warnings.append("No hay registros DNS ni datos de registro. Si no estás sin conexión, el dominio podría estar libre: compruébalo en Buscar.")
            } else {
                report.warnings.append("No se encontraron registros DNS. El dominio está registrado pero no tiene DNS configurado.")
            }
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

    private func fetchHTTP(_ domain: String) async -> HTTPInfo? {
        if let info = await fetchHTTP(domain, method: "HEAD") {
            return info
        }
        return await fetchHTTP(domain, method: "GET")
    }

    private func fetchHTTP(_ domain: String, method: String) async -> HTTPInfo? {
        guard let url = URL(string: "https://\(domain)/") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8
        guard let (_, http) = try? await HTTPClient.data(for: request) else { return nil }
        return HTTPInfo(
            statusCode: http.statusCode,
            finalURL: http.url?.absoluteString ?? url.absoluteString,
            server: http.value(forHTTPHeaderField: "Server"),
            contentType: http.value(forHTTPHeaderField: "Content-Type")
        )
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
        if case .registered(let info)? = try? await RDAPClient.shared.lookup(domain) {
            return info
        }
        #if os(macOS)
        return await fetchWhois(domain)
        #else
        return nil
        #endif
    }

    private func fetchGeo(ip: String) async -> GeoInfo? {
        guard let url = URL(string: "https://ipwho.is/\(ip)"),
              let (data, _) = try? await HTTPClient.data(for: URLRequest(url: url)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
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
    }

    #if os(macOS)
    private func fetchWhois(_ domain: String) async -> RegistrationInfo? {
        let output = await run("/usr/bin/whois", [domain])
        guard !output.isEmpty else { return nil }

        func firstMatch(_ keys: [String]) -> String? {
            for line in output.split(whereSeparator: \.isNewline) {
                let text = String(line)
                for key in keys where text.lowercased().hasPrefix(key.lowercased()) {
                    let value = text.split(separator: ":", maxSplits: 1).dropFirst().first?
                        .trimmingCharacters(in: .whitespaces)
                    if let value, !value.isEmpty { return value }
                }
            }
            return nil
        }

        let registrar = firstMatch(["Registrar:", "registrar:"])
        let created = firstMatch(["Creation Date:", "created:", "Created On:"])
        guard registrar != nil || created != nil else { return nil }

        return RegistrationInfo(
            registrar: registrar,
            created: created,
            expires: firstMatch(["Registry Expiry Date:", "Expiry Date:", "expires:"]),
            updated: firstMatch(["Updated Date:", "last-modified:"]),
            statuses: [],
            rdapNameservers: [],
            source: "WHOIS"
        )
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
    #endif
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
        info = CertificateInfo.make(from: trust)
    }
}
