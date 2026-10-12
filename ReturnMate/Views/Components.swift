import SwiftUI

struct PurchaseRoute: Hashable {
    var id: UUID
}

enum DeadlineTone {
    case overdue, urgent, soon, ok, unknown, inactive

    var color: Color {
        switch self {
        case .overdue: return .red
        case .urgent: return .orange
        case .soon: return .yellow
        case .ok: return .green
        case .unknown: return .gray
        case .inactive: return .secondary
        }
    }

    static func of(_ p: Purchase, days: Int?) -> DeadlineTone {
        guard p.status.deadlineMatters else { return .inactive }
        guard let days else { return .unknown }
        if days < 0 { return .overdue }
        if days <= 3 { return .urgent }
        if days <= 7 { return .soon }
        return .ok
    }
}

struct DeadlineBadge: View {
    let purchase: Purchase
    let days: Int?

    var body: some View {
        let tone = DeadlineTone.of(purchase, days: days)
        HStack(spacing: 4) {
            if purchase.deadline?.verification == .proposed && purchase.status.deadlineMatters {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
            }
            Text(label)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tone.color.opacity(0.18), in: Capsule())
        .foregroundStyle(tone == .soon ? Color.orange : tone.color)
        .accessibilityLabel(label + (purchase.deadline?.verification == .proposed ? ", da verificare" : ""))
    }

    private var label: String {
        if !purchase.status.deadlineMatters { return purchase.status.title }
        guard let days else { return "Scadenza da inserire" }
        return Formatters.daysLabel(days)
    }
}

struct StatusChip: View {
    let status: ReturnStatus
    var body: some View {
        Label(status.title, systemImage: status.symbol)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
}

struct ThumbnailView: View {
    let purchase: Purchase
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let id = purchase.imageAttachmentID ?? purchase.attachments.first(where: \.isImage)?.id,
               let att = purchase.attachments.first(where: { $0.id == id }),
               let image = AttachmentStore.loadImage(att) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.accentColor.opacity(0.12)
                    Text(String(purchase.store.prefix(1)).uppercased())
                        .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

struct PurchaseRow: View {
    @Environment(DataStore.self) private var store
    let purchase: Purchase

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(purchase: purchase)
            VStack(alignment: .leading, spacing: 3) {
                Text(purchase.productName).font(.body.weight(.medium)).lineLimit(1)
                Text("\(purchase.store) · \(Formatters.money(purchase.totalPrice, currency: purchase.currency))")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if let d = purchase.deadline, purchase.status.deadlineMatters {
                    Text("Entro \(Formatters.date(d.date, timeZone: store.settings.timeZone))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                DeadlineBadge(purchase: purchase, days: store.daysRemaining(purchase))
                if purchase.status != .toEvaluate && purchase.status.deadlineMatters {
                    Text(purchase.status.title).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct WarningList: View {
    let warnings: [String]
    var body: some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(warnings, id: \.self) { w in
                    Label(w, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

/// Campo per importi con tastiera decimale.
struct DecimalField: View {
    let title: String
    @Binding var value: Decimal?
    @State private var text: String = ""
    @State private var loaded = false

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .onAppear {
                if !loaded { text = Formatters.decimalString(value); loaded = true }
            }
            .onChange(of: text) { _, new in
                value = new.isEmpty ? nil : Formatters.parseDecimal(new)
            }
    }
}

/// DatePicker opzionale: un interruttore attiva la data.
struct OptionalDatePicker: View {
    let title: String
    @Binding var date: Date?
    var timeZone: TimeZone = .current

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { date != nil },
            set: { on in date = on ? (date ?? Date()) : nil }
        ))
        if date != nil {
            DatePicker(title, selection: Binding(get: { date ?? Date() }, set: { date = $0 }), displayedComponents: .date)
                .environment(\.timeZone, timeZone)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let symbol: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }
}

extension View {
    func cardStyle() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
