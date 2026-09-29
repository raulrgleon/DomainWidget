import SwiftUI

struct DomainRoute: Hashable {
    let domain: String
}

extension AvailabilityStatus {
    var tint: Color {
        switch self {
        case .available: return .green
        case .likelyAvailable: return .mint
        case .taken: return .red
        case .likelyTaken: return .orange
        case .unknown: return .gray
        }
    }
}

struct StatusBadge: View {
    let status: AvailabilityStatus

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(status.tint)
            .background(status.tint.opacity(0.15), in: Capsule())
            .fixedSize()
    }
}

enum ExpiryUrgency {
    case expired, critical, warning, normal

    static let criticalDays = 7

    static func daysLeft(until date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: date).day ?? 0
    }

    static func level(for date: Date, warningDays: Int) -> ExpiryUrgency {
        let days = daysLeft(until: date)
        if days < 0 { return .expired }
        if days <= criticalDays { return .critical }
        if days <= warningDays { return .warning }
        return .normal
    }

    var tint: Color? {
        switch self {
        case .expired, .critical: return .red
        case .warning: return .orange
        case .normal: return nil
        }
    }

    var isUrgent: Bool { self != .normal }
}

/// Días que faltan para caducar, resaltado en rojo (≤7) o naranja (≤ aviso configurado).
struct ExpiryBadge: View {
    let date: Date
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let level = ExpiryUrgency.level(for: date, warningDays: settings.expiryWarningDays)
        let days = ExpiryUrgency.daysLeft(until: date)
        let text: String = switch level {
        case .expired: "Caducó hace \(-days) d"
        case .critical, .warning: days == 0 ? "Caduca hoy" : "Caduca en \(days) d"
        case .normal: "Caduca \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        if let tint = level.tint {
            HStack(spacing: 3) {
                Image(systemName: level == .warning ? "clock.badge.exclamationmark" : "exclamationmark.triangle.fill")
                Text(text).lineLimit(1)
            }
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(.white)
                .background(tint, in: Capsule())
                .fixedSize()
        } else {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// Fila de un dominio con su estado, favorito y acciones.
struct AvailabilityRow: View {
    let domain: String
    var result: DomainAvailability?
    var knownStatus: AvailabilityStatus?
    var expires: Date?
    var isPending = false
    var detail: String?
    var onTap: (() -> Void)?

    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings

    private var status: AvailabilityStatus? { result?.status ?? knownStatus }
    private var expiry: Date? { status?.isAvailable == true ? nil : (result?.expires ?? expires) }
    private var urgency: ExpiryUrgency {
        expiry.map { ExpiryUrgency.level(for: $0, warningDays: settings.expiryWarningDays) } ?? .normal
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isPending && result == nil {
                    ProgressView().controlSize(.small)
                } else if let status {
                    Image(systemName: status.systemImage).foregroundStyle(status.tint)
                } else {
                    Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                }
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(domain)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if let status {
                        StatusBadge(status: status)
                    }
                    if let expiry {
                        ExpiryBadge(date: expiry)
                    }
                    if let subtitle, !urgency.isUrgent {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if let subtitle, urgency.isUrgent {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if status?.isAvailable == true {
                RegisterMenu(domain: domain, compact: true)
            }

            Button {
                library.toggleFavorite(domain, status: status)
            } label: {
                Image(systemName: library.isFavorite(domain) ? "star.fill" : "star")
                    .foregroundStyle(library.isFavorite(domain) ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .help(library.isFavorite(domain) ? "Quitar de favoritos" : "Añadir a favoritos")
        }
        .contentShape(Rectangle())
        .listRowBackground(urgency.tint.map { $0.opacity(0.10) })
        .onTapGesture {
            if let onTap { onTap() } else { router.analyze(domain) }
        }
        .contextMenu {
            DomainActionsContent(domain: domain, status: status, expires: expiry)
        }
        .swipeActions(edge: .trailing) {
            Button {
                library.toggleFavorite(domain, status: status)
            } label: {
                Label("Favorito", systemImage: library.isFavorite(domain) ? "star.slash" : "star")
            }
            .tint(.yellow)
            WatchButton(domain: domain, status: status, expires: expiry)
                .tint(.blue)
        }
    }

    private var subtitle: String? {
        if let detail { return detail }
        guard let result else { return isPending ? "Comprobando…" : nil }
        switch result.status {
        case .taken:
            return urgency.isUrgent ? nil : result.registrar
        case .available:
            return nil
        case .likelyAvailable, .likelyTaken:
            return "Sin RDAP · deducido por DNS"
        case .unknown:
            return result.note
        }
    }
}

struct RegisterMenu: View {
    let domain: String
    var compact = false
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Menu {
            ForEach(Registrar.allCases) { registrar in
                if let url = registrar.url(for: domain, affiliate: settings.affiliateParameters[registrar.rawValue]) {
                    Link(registrar.name, destination: url)
                }
            }
        } label: {
            if compact {
                Image(systemName: "cart")
            } else {
                Label("Registrar en…", systemImage: "cart")
            }
        }
        .menuIndicator(compact ? .hidden : .visible)
        .fixedSize()
        .help("Registrar")
    }
}

struct WatchButton: View {
    let domain: String
    var status: AvailabilityStatus?
    var expires: Date?
    @Environment(LibraryStore.self) private var library

    var body: some View {
        Button {
            let adding = !library.isWatched(domain)
            library.toggleWatch(domain, status: status, expires: expires)
            if adding {
                Task { _ = await WatchlistMonitor.requestNotificationPermission() }
            }
        } label: {
            Label(library.isWatched(domain) ? "Dejar de vigilar" : "Vigilar", systemImage: library.isWatched(domain) ? "eye.slash" : "eye")
        }
    }
}

/// Acciones comunes de un dominio (menú contextual y botón de la barra de herramientas).
struct DomainActionsContent: View {
    let domain: String
    var status: AvailabilityStatus?
    var expires: Date?

    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            library.toggleFavorite(domain, status: status)
        } label: {
            Label(library.isFavorite(domain) ? "Quitar de favoritos" : "Añadir a favoritos",
                  systemImage: library.isFavorite(domain) ? "star.slash" : "star")
        }
        WatchButton(domain: domain, status: status, expires: expires)
        Button {
            router.analyze(domain)
        } label: {
            Label("Analizar", systemImage: "doc.text.magnifyingglass")
        }
        RegisterMenu(domain: domain)
        Divider()
        Button {
            Clipboard.copy(domain)
        } label: {
            Label("Copiar", systemImage: "doc.on.doc")
        }
        ShareLink(item: domain)
    }
}

struct DomainActionsMenu: View {
    let domain: String
    var status: AvailabilityStatus?
    var expires: Date?

    var body: some View {
        Menu {
            DomainActionsContent(domain: domain, status: status, expires: expires)
        } label: {
            Label("Acciones", systemImage: "ellipsis.circle")
        }
    }
}

struct TLDPicker: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(settings.allTLDs, id: \.self) { tld in
                    Toggle(".\(tld)", isOn: Binding(
                        get: { settings.selectedTLDs.contains(tld) },
                        set: { _ in settings.toggleTLD(tld) }
                    ))
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
