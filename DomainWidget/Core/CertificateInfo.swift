import Foundation
import Security

/// Lectura de certificados con APIs de Security disponibles en macOS e iOS.
enum CertificateInfo {
    static func make(from trust: SecTrust) -> SSLInfo? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else { return nil }

        let subject = SecCertificateCopySubjectSummary(leaf) as String? ?? "Desconocido"
        let issuer = chain.count > 1
            ? (SecCertificateCopySubjectSummary(chain[1]) as String? ?? "Desconocido")
            : "Autofirmado"
        let isTrusted = SecTrustEvaluateWithError(trust, nil)

        let validity = validityDates(der: SecCertificateCopyData(leaf) as Data)
        let until = validity?.until
        let remaining = until.flatMap { Calendar.current.dateComponents([.day], from: Date(), to: $0).day }

        return SSLInfo(
            subject: subject,
            issuer: issuer,
            validFrom: validity?.from,
            validUntil: until,
            isExpired: until.map { $0 < Date() } ?? false,
            daysRemaining: remaining,
            isTrusted: isTrusted
        )
    }

    /// Extrae notBefore/notAfter del TBSCertificate (X.509 en DER).
    static func validityDates(der: Data) -> (from: Date, until: Date)? {
        var root = DERReader(bytes: ArraySlice(der))
        guard let certificate = root.next(), certificate.tag == 0x30 else { return nil }

        var certificateReader = DERReader(bytes: certificate.value)
        guard let tbs = certificateReader.next(), tbs.tag == 0x30 else { return nil }

        var tbsReader = DERReader(bytes: tbs.value)
        var element = tbsReader.next()
        if element?.tag == 0xA0 {
            element = tbsReader.next()
        }
        guard element?.tag == 0x02,
              tbsReader.next() != nil,
              tbsReader.next() != nil,
              let validity = tbsReader.next(), validity.tag == 0x30 else { return nil }

        var validityReader = DERReader(bytes: validity.value)
        guard let notBefore = validityReader.next(),
              let notAfter = validityReader.next(),
              let from = parseTime(notBefore),
              let until = parseTime(notAfter) else { return nil }
        return (from, until)
    }

    private static func parseTime(_ element: DERElement) -> Date? {
        guard var text = String(bytes: element.value, encoding: .ascii) else { return nil }
        switch element.tag {
        case 0x17:
            guard text.count >= 12, let year = Int(text.prefix(2)) else { return nil }
            text = (year < 50 ? "20" : "19") + text
        case 0x18:
            break
        default:
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.date(from: String(text.prefix(14)))
    }
}

struct DERElement {
    let tag: UInt8
    let value: ArraySlice<UInt8>
}

struct DERReader {
    var bytes: ArraySlice<UInt8>

    mutating func next() -> DERElement? {
        guard let tag = bytes.first else { return nil }
        var index = bytes.startIndex + 1
        guard index < bytes.endIndex else { return nil }

        var length = Int(bytes[index])
        index += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count > 0, count <= 4, index + count <= bytes.endIndex else { return nil }
            length = 0
            for _ in 0..<count {
                length = (length << 8) | Int(bytes[index])
                index += 1
            }
        }
        guard index + length <= bytes.endIndex else { return nil }

        let value = bytes[index..<(index + length)]
        bytes = bytes[(index + length)...]
        return DERElement(tag: tag, value: value)
    }
}
