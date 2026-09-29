import Foundation

/// Enlaces directos para registrar un dominio. Los parámetros de afiliado se configuran en Ajustes
/// (por ejemplo `aff=123`) y se añaden a la URL.
enum Registrar: String, CaseIterable, Identifiable {
    case namecheap, porkbun, cloudflare, godaddy

    var id: String { rawValue }

    var name: String {
        switch self {
        case .namecheap: return "Namecheap"
        case .porkbun: return "Porkbun"
        case .cloudflare: return "Cloudflare"
        case .godaddy: return "GoDaddy"
        }
    }

    func url(for domain: String, affiliate: String? = nil) -> URL? {
        let encoded = domain.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? domain
        let base: String
        switch self {
        case .namecheap: base = "https://www.namecheap.com/domains/registration/results/?domain=\(encoded)"
        case .porkbun: base = "https://porkbun.com/checkout/search?q=\(encoded)"
        case .cloudflare: base = "https://dash.cloudflare.com/?to=/:account/domains/register/\(encoded)"
        case .godaddy: base = "https://www.godaddy.com/domainsearch/find?domainToCheck=\(encoded)"
        }
        guard var components = URLComponents(string: base) else { return nil }
        if let affiliate, !affiliate.isEmpty {
            let extra = URLComponents(string: "?" + affiliate.trimmingCharacters(in: CharacterSet(charactersIn: "?&")))?.queryItems ?? []
            components.queryItems = (components.queryItems ?? []) + extra
        }
        return components.url
    }
}
