import Foundation

// Prueba de humo del núcleo contra la red real.
// Uso: scripts/smoke-test.sh

func check(_ condition: Bool, _ message: String) {
    print(condition ? "OK   \(message)" : "FAIL \(message)")
    if !condition { failures += 1 }
}

var failures = 0

let dns = DNSClient()
let a = try await dns.query("apple.com", .a)
check(!a.records.isEmpty, "DNS A apple.com -> \(a.records.prefix(2))")
let nx = try await dns.query("zz-no-existe-\(Int.random(in: 100000...999999)).com", .ns)
check(nx.isNXDomain, "DNS NXDOMAIN para dominio inventado")

let registered = try await RDAPClient.shared.lookup("google.com")
if case .registered(let info) = registered {
    check(info.expiryDate != nil, "RDAP google.com registrado, caduca \(info.expires ?? "?"), registrador \(info.registrar ?? "?")")
} else {
    check(false, "RDAP google.com debería estar registrado")
}
let free = try await RDAPClient.shared.lookup("zz-no-existe-\(Int.random(in: 100000...999999)).com")
if case .notFound = free { check(true, "RDAP dominio libre -> 404") } else { check(false, "RDAP dominio libre") }

let service = DomainLookupService()
let report = try await service.lookup("https://www.wikipedia.org/wiki")
check(report.domain == "www.wikipedia.org", "Normalización de URL -> \(report.domain)")
check(report.ssl?.validUntil != nil, "SSL fechas: \(report.ssl?.validFrom?.description ?? "-") .. \(report.ssl?.validUntil?.description ?? "-"), emisor \(report.ssl?.issuer ?? "-")")
check(report.ssl?.isTrusted == true, "SSL de confianza")
check(!report.nameservers.isEmpty || !report.cname.isEmpty, "DNS NS/CNAME en informe")

let availability = AvailabilityService()
let results = await availability.check(domains: ["google.com", "zz-libre-\(Int.random(in: 100000...999999)).com", "zz-libre-\(Int.random(in: 100000...999999)).dev"])
for result in results {
    print("     \(result.domain): \(result.status.rawValue) [\(result.source)] \(result.note ?? "")")
}
check(results.first { $0.domain == "google.com" }?.status == .taken, "Disponibilidad google.com = ocupado")
check(results.filter { $0.status == .available }.count == 2, "Disponibilidad nombres inventados = libres")

let suggestions = SuggestionEngine.variations(for: "cafe rapido", limit: 12)
check(suggestions.contains("caferapido") && suggestions.contains("cafe-rapido"), "Sugerencias: \(suggestions.prefix(8))")
check(BulkParser.parse("a.com, b.io\nc\n# comentario\nd.dev;e.net", defaultTLD: "com") == ["a.com", "b.io", "c.com", "d.dev", "e.net"], "Parser masivo")

print(failures == 0 ? "\nTodo OK" : "\n\(failures) fallos")
exit(failures == 0 ? 0 : 1)
