import Foundation

enum DNSRecordType: String, CaseIterable {
    case a = "A"
    case aaaa = "AAAA"
    case cname = "CNAME"
    case mx = "MX"
    case ns = "NS"
    case txt = "TXT"
    case soa = "SOA"

    var code: Int {
        switch self {
        case .a: return 1
        case .ns: return 2
        case .cname: return 5
        case .soa: return 6
        case .mx: return 15
        case .txt: return 16
        case .aaaa: return 28
        }
    }
}

struct DNSResult {
    let status: Int
    let records: [String]

    var isNXDomain: Bool { status == 3 }
}

/// DNS sobre HTTPS (JSON), disponible igual en macOS e iOS.
struct DNSClient {
    private static let resolvers = [
        "https://cloudflare-dns.com/dns-query",
        "https://dns.google/resolve"
    ]

    func query(_ name: String, _ type: DNSRecordType) async throws -> DNSResult {
        var lastError: Error = NetworkError.invalidResponse
        for resolver in Self.resolvers {
            do {
                return try await query(name, type, resolver: resolver)
            } catch NetworkError.offline {
                throw NetworkError.offline
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func records(_ name: String, _ type: DNSRecordType) async -> [String] {
        (try? await query(name, type).records) ?? []
    }

    private func query(_ name: String, _ type: DNSRecordType, resolver: String) async throws -> DNSResult {
        guard var components = URLComponents(string: resolver) else { throw NetworkError.invalidResponse }
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "type", value: type.rawValue)
        ]
        guard let url = components.url else { throw NetworkError.invalidResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")

        let (data, response) = try await HTTPClient.data(for: request)
        guard (200...299).contains(response.statusCode) else {
            throw NetworkError.server(status: response.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["Status"] as? Int else {
            throw NetworkError.invalidResponse
        }

        let answers = json["Answer"] as? [[String: Any]] ?? []
        let records = answers
            .filter { ($0["type"] as? Int) == type.code }
            .compactMap { $0["data"] as? String }
            .map { Self.clean($0, type: type) }
            .filter { !$0.isEmpty }
        return DNSResult(status: status, records: records)
    }

    private static func clean(_ value: String, type: DNSRecordType) -> String {
        var result = value.trimmingCharacters(in: .whitespaces)
        if type == .txt {
            result = result
                .replacingOccurrences(of: "\" \"", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        } else if result.hasSuffix(".") {
            result.removeLast()
        }
        return result
    }
}
