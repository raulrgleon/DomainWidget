import Foundation

/// Genera variaciones de un nombre sin conexión (prefijos, sufijos, guiones, sinónimos).
enum SuggestionEngine {
    static let prefixes = ["get", "try", "use", "my", "go", "the", "hey", "hola", "mi"]
    static let suffixes = ["app", "hq", "labs", "hub", "ly", "io", "online", "pro", "now", "web"]

    static let synonyms: [String: [String]] = [
        "rapido": ["veloz", "express", "flash", "fast"],
        "fast": ["quick", "rapid", "swift", "flash"],
        "casa": ["hogar", "home", "nido"],
        "home": ["house", "nest", "casa"],
        "tienda": ["shop", "store", "mercado"],
        "shop": ["store", "market", "mart"],
        "cafe": ["coffee", "brew", "espresso"],
        "coffee": ["brew", "bean", "cafe"],
        "dominio": ["domain", "web", "sitio"],
        "domain": ["site", "web", "name"],
        "viaje": ["travel", "trip", "ruta"],
        "travel": ["trip", "journey", "voyage"],
        "salud": ["health", "vida", "bienestar"],
        "health": ["care", "well", "vital"],
        "dinero": ["money", "cash", "finanzas"],
        "money": ["cash", "coin", "fund"],
        "comida": ["food", "sabor", "cocina"],
        "food": ["eats", "kitchen", "bite"],
        "smart": ["clever", "bright", "genius"],
        "cloud": ["sky", "nube", "nimbus"]
    ]

    static func variations(for input: String, limit: Int = 30) -> [String] {
        let words = input.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map(DomainName.sanitizeLabel)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }

        let base = words.joined()
        var candidates: [String] = [base]

        if words.count > 1 {
            candidates.append(words.joined(separator: "-"))
            candidates.append(String(words.reversed().joined()))
            candidates.append(words.map { String($0.prefix(1)) }.joined() + (words.last ?? ""))
        }

        for (index, word) in words.enumerated() {
            for synonym in synonyms[word] ?? [] {
                var replaced = words
                replaced[index] = DomainName.sanitizeLabel(synonym)
                candidates.append(replaced.joined())
            }
        }

        candidates += prefixes.map { $0 + base }
        candidates += suffixes.map { base + $0 }

        let withoutVowels = base.replacingOccurrences(of: #"(?<=.)[aeiou](?=[^aeiou])"#, with: "", options: .regularExpression)
        if withoutVowels.count >= 3 { candidates.append(withoutVowels) }
        if base.hasSuffix("s") { candidates.append(String(base.dropLast())) } else { candidates.append(base + "s") }

        var seen = Set<String>()
        return candidates
            .filter(DomainName.isValidLabel)
            .filter { seen.insert($0).inserted }
            .prefix(limit)
            .map { $0 }
    }
}

/// Sugerencias opcionales con una API compatible con OpenAI (clave guardada en el Llavero).
struct AISuggestionClient {
    let endpoint: URL
    let model: String
    let apiKey: String

    func suggestions(for idea: String, count: Int = 15) async throws -> [String] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let prompt = """
        Propón \(count) nombres cortos y memorables para un dominio web a partir de esta idea: "\(idea)".
        Solo la parte del nombre, sin TLD, en minúsculas, letras, números o guiones.
        Responde únicamente con un array JSON de strings.
        """
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.9,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await HTTPClient.data(for: request)
        switch response.statusCode {
        case 200...299: break
        case 401, 403: throw NetworkError.other("La clave de la API de IA no es válida.")
        case 429: throw NetworkError.rateLimited(host: endpoint.host ?? "IA")
        default: throw NetworkError.server(status: response.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NetworkError.invalidResponse
        }
        return Self.parseNames(content)
    }

    static func parseNames(_ content: String) -> [String] {
        let jsonSlice: Substring
        if let start = content.firstIndex(of: "["), let end = content.lastIndex(of: "]"), start < end {
            jsonSlice = content[start...end]
        } else {
            jsonSlice = Substring(content)
        }
        let names: [String]
        if let data = jsonSlice.data(using: .utf8), let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
            names = array
        } else {
            names = content.components(separatedBy: CharacterSet(charactersIn: ",\n"))
        }
        var seen = Set<String>()
        return names
            .map { DomainName.split($0).label }
            .filter(DomainName.isValidLabel)
            .filter { seen.insert($0).inserted }
    }
}
