import Foundation

struct DomainReport: Identifiable {
    let id = UUID()
    let domain: String
    let queriedAt: Date
    var ipv4: [String] = []
    var ipv6: [String] = []
    var mx: [String] = []
    var nameservers: [String] = []
    var txt: [String] = []
    var cname: [String] = []
    var http: HTTPInfo?
    var ssl: SSLInfo?
    var registration: RegistrationInfo?
    var geo: GeoInfo?
    var warnings: [String] = []
}

struct HTTPInfo {
    let statusCode: Int
    let finalURL: String
    let server: String?
    let contentType: String?
}

struct SSLInfo {
    let subject: String
    let issuer: String
    let validFrom: Date?
    let validUntil: Date?
    let isExpired: Bool
    let daysRemaining: Int?
    let isTrusted: Bool
}

struct RegistrationInfo {
    let registrar: String?
    let created: String?
    let expires: String?
    let updated: String?
    let statuses: [String]
    let rdapNameservers: [String]
    let source: String
}

struct GeoInfo {
    let ip: String
    let city: String?
    let region: String?
    let country: String?
    let org: String?
    let asn: String?
}

enum LookupError: LocalizedError {
    case emptyInput
    case invalidDomain
    case lookupFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Escribe un dominio para consultar."
        case .invalidDomain:
            return "El dominio no parece válido."
        case .lookupFailed(let message):
            return message
        }
    }
}
