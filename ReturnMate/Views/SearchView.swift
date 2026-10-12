import SwiftUI

enum PurchaseSection: String, CaseIterable, Identifiable {
    case active, kept, inProgress, refunded, archived, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .active: return "Attivi"
        case .kept: return "Tenuti"
        case .inProgress: return "Resi in corso"
        case .refunded: return "Rimborsati"
        case .archived: return "Archivio"
        case .all: return "Tutti"
        }
    }

    func contains(_ p: Purchase) -> Bool {
        switch self {
        case .archived: return p.isArchived
        case .all: return true
        case .active: return !p.isArchived && [.toEvaluate, .toReturn].contains(p.status)
        case .kept: return !p.isArchived && p.status == .keep
        case .inProgress: return !p.isArchived && p.status.isReturnInProgress
        case .refunded: return !p.isArchived && (p.status == .refunded || p.status == .closed || p.refund.confirmedByUser)
        }
    }
}

enum DeadlineFilter: String, CaseIterable, Identifiable {
    case any, overdue, week, month, unverified, missing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .any: return "Qualsiasi"
        case .overdue: return "Scadute"
        case .week: return "Entro 7 giorni"
        case .month: return "Entro 30 giorni"
        case .unverified: return "Da verificare"
        case .missing: return "Senza scadenza"
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case deadline, recent, amount, name
    var id: String { rawValue }
    var title: String {
        switch self {
        case .deadline: return "Scadenza"
        case .recent: return "Più recenti"
        case .amount: return "Importo"
        case .name: return "Nome"
        }
    }
}

struct PurchaseFilters: Equatable {
    var status: ReturnStatus?
    var deadline: DeadlineFilter = .any
    var minAmount: Decimal?
    var maxAmount: Decimal?
    var from: Date?
    var to: Date?

    var isActive: Bool { self != PurchaseFilters() }

    static func matchesText(_ p: Purchase, _ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return [p.productName, p.store, p.orderNumber, p.returnInfo.trackingNumber, p.returnInfo.reference]
            .contains { $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    func matches(_ p: Purchase, now: Date, calendar: Calendar) -> Bool {
        if let status, p.status != status { return false }
        let days = p.deadline.map { DeadlineEngine.daysRemaining(until: $0.date, now: now, calendar: calendar) }
        switch deadline {
        case .any: break
        case .overdue: if !(p.status.deadlineMatters && (days ?? 0) < 0) { return false }
        case .week: if !(p.status.deadlineMatters && days != nil && days! >= 0 && days! <= 7) { return false }
        case .month: if !(p.status.deadlineMatters && days != nil && days! >= 0 && days! <= 30) { return false }
        case .unverified: if p.deadline?.verification != .proposed { return false }
        case .missing: if p.deadline != nil { return false }
        }
        let amount = p.totalPrice ?? 0
        if let minAmount, amount < minAmount { return false }
        if let maxAmount, amount > maxAmount { return false }
        let date = p.orderDate ?? p.deliveryDate ?? p.createdAt
        if let from, date < calendar.startOfDay(for: from) { return false }
        if let to, let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to)), date >= end { return false }
        return true
    }
}

struct SearchView: View {
    @Environment(DataStore.self) private var store
    @State private var query = ""
    @State private var section: PurchaseSection = .active
    @State private var filters = PurchaseFilters()
    @State private var sort: SortOrder = .deadline
    @State private var showFilters = false

    var body: some View {
        let now = Date()
        let results = store.purchases
            .filter { section.contains($0) }
            .filter { PurchaseFilters.matchesText($0, query) }
            .filter { filters.matches($0, now: now, calendar: store.calendar) }
            .sorted(by: sorter(now: now))

        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(PurchaseSection.allCases) { s in
                            let count = store.purchases.filter { s.contains($0) }.count
                            Button { section = s } label: {
                                Text("\(s.title) \(count)")
                                    .font(.subheadline)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(section == s ? Color.accentColor : Color(.secondarySystemGroupedBackground), in: Capsule())
                                    .foregroundStyle(section == s ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if results.isEmpty {
                EmptyStateView(title: "Nessun risultato", message: "Modifica la ricerca o i filtri.", symbol: "magnifyingglass")
            }
            ForEach(results) { p in
                NavigationLink(value: PurchaseRoute(id: p.id)) { PurchaseRow(purchase: p) }
                    .swipeActions(edge: .trailing) {
                        Button {
                            store.setArchived(p.id, !p.isArchived)
                        } label: {
                            Label(p.isArchived ? "Ripristina" : "Archivia", systemImage: p.isArchived ? "tray.and.arrow.up" : "archivebox")
                        }
                        .tint(.indigo)
                    }
            }
        }
        .searchable(text: $query, prompt: "Nome, negozio, numero d'ordine")
        .navigationTitle("Acquisti")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Ordina per", selection: $sort) {
                        ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showFilters = true } label: {
                    Image(systemName: filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showFilters) {
            NavigationStack { FiltersView(filters: $filters) }
        }
    }

    private func sorter(now: Date) -> (Purchase, Purchase) -> Bool {
        switch sort {
        case .deadline: return { store.urgency($0, now: now) < store.urgency($1, now: now) }
        case .recent: return { ($0.orderDate ?? $0.createdAt) > ($1.orderDate ?? $1.createdAt) }
        case .amount: return { ($0.totalPrice ?? 0) > ($1.totalPrice ?? 0) }
        case .name: return { $0.productName.localizedCaseInsensitiveCompare($1.productName) == .orderedAscending }
        }
    }
}

struct FiltersView: View {
    @Binding var filters: PurchaseFilters
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Stato") {
                Picker("Stato", selection: $filters.status) {
                    Text("Tutti").tag(ReturnStatus?.none)
                    ForEach(ReturnStatus.allCases) { Text($0.title).tag(ReturnStatus?.some($0)) }
                }
            }
            Section("Scadenza") {
                Picker("Scadenza", selection: $filters.deadline) {
                    ForEach(DeadlineFilter.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Importo") {
                HStack { Text("Minimo"); DecimalField(title: "—", value: $filters.minAmount) }
                HStack { Text("Massimo"); DecimalField(title: "—", value: $filters.maxAmount) }
            }
            Section("Periodo d'acquisto") {
                OptionalDatePicker(title: "Dal", date: $filters.from)
                OptionalDatePicker(title: "Al", date: $filters.to)
            }
            Section {
                Button("Azzera filtri", role: .destructive) { filters = PurchaseFilters() }
            }
        }
        .navigationTitle("Filtri")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } }
        }
    }
}
