import Foundation

enum NetworkError: LocalizedError, Equatable {
    case offline
    case timeout
    case rateLimited(host: String)
    case server(status: Int)
    case invalidResponse
    case other(String)

    var errorDescription: String? {
        switch self {
        case .offline:
            return "Sin conexión a internet."
        case .timeout:
            return "El servidor tardó demasiado en responder."
        case .rateLimited(let host):
            return "\(host) está limitando las consultas. Prueba en unos segundos."
        case .server(let status):
            return "El servidor respondió con un error (\(status))."
        case .invalidResponse:
            return "Respuesta no válida del servidor."
        case .other(let message):
            return message
        }
    }
}

enum HTTPClient {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["User-Agent": "DomainWidget/2.0"]
        return URLSession(configuration: config)
    }()

    static func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            return (data, http)
        } catch let error as URLError {
            throw map(error)
        }
    }

    static func map(_ error: URLError) -> NetworkError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        case .timedOut:
            return .timeout
        default:
            return .other(error.localizedDescription)
        }
    }
}
