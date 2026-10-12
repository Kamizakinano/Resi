import SwiftUI
import Charts

struct StatsView: View {
    @Environment(DataStore.self) private var store
    @Environment(PremiumManager.self) private var premium
    @State private var period: Period = .all

    enum Period: String, CaseIterable, Identifiable {
        case month, quarter, year, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .month: return "30 gg"
            case .quarter: return "3 mesi"
            case .year: return "12 mesi"
            case .all: return "Tutto"
            }
        }
        var days: Int? {
            switch self {
            case .month: return 30
            case .quarter: return 90
            case .year: return 365
            case .all: return nil
            }
        }
    }

    var body: some View {
        let now = Date()
        let cal = store.calendar
        let purchases = store.purchases.filter { p in
            guard let days = period.days else { return true }
            let date = p.orderDate ?? p.deliveryDate ?? p.createdAt
            return date >= (cal.date(byAdding: .day, value: -days, to: now) ?? now)
        }
        let s = Statistics.summary(purchases, now: now, calendar: cal)
        let currency = store.settings.currency

        List {
            Section {
                Picker("Periodo", selection: $period) {
                    ForEach(Period.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    SummaryCard(title: "Totale acquisti", value: Formatters.money(s.totalPurchased, currency: currency), symbol: "bag")
                    SummaryCard(title: "Ancora restituibile", value: Formatters.money(s.returnableValue, currency: currency), symbol: "arrow.uturn.backward")
                    SummaryCard(title: "Rimborsi attesi", value: Formatters.money(s.refundsExpected, currency: currency), symbol: "hourglass", tint: .orange)
                    SummaryCard(title: "Rimborsi ricevuti", value: Formatters.money(s.refundsReceived, currency: currency), symbol: "checkmark.circle", tint: .green)
                    SummaryCard(title: "Resi completati", value: "\(s.completedReturns)", symbol: "shippingbox")
                    SummaryCard(title: "Scadenze superate", value: "\(s.missedDeadlines)", symbol: "exclamationmark.octagon", tint: s.missedDeadlines > 0 ? .red : .secondary)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                LabeledContent("Denaro recuperato (netto costi)", value: Formatters.money(s.netRecovered, currency: currency))
                LabeledContent("Costi di reso", value: Formatters.money(s.returnCosts, currency: currency))
                LabeledContent("Valore dei prodotti restituiti", value: Formatters.money(s.returnedProductsValue, currency: currency))
            } header: {
                Text("Recuperato vs restituito")
            } footer: {
                Text("Il denaro recuperato considera solo i rimborsi che hai confermato, al netto dei costi di reso. Il valore dei prodotti restituiti è il prezzo pagato per gli stessi prodotti.")
            }

            if premium.isPremium {
                let byStore = Array(Statistics.byStore(purchases).prefix(8))
                if !byStore.isEmpty {
                    Section("Per negozio") {
                        Chart(byStore) { g in
                            BarMark(x: .value("Speso", (g.purchased as NSDecimalNumber).doubleValue), y: .value("Negozio", g.key))
                                .foregroundStyle(Color.accentColor)
                        }
                        .frame(height: CGFloat(byStore.count) * 34 + 30)
                        ForEach(byStore) { g in
                            LabeledContent("\(g.key) (\(g.count))", value: "\(Formatters.money(g.purchased, currency: currency)) · rimb. \(Formatters.money(g.refunded, currency: currency))")
                        }
                    }
                }
                let byMonth = Statistics.byMonth(purchases, calendar: cal).filter { $0.key != "Senza data" }
                if !byMonth.isEmpty {
                    Section("Per mese") {
                        Chart(byMonth) { g in
                            BarMark(x: .value("Mese", g.key), y: .value("Speso", (g.purchased as NSDecimalNumber).doubleValue))
                                .foregroundStyle(Color.accentColor)
                        }
                        .frame(height: 180)
                    }
                }
            } else {
                Section {
                    NavigationLink("Statistiche avanzate con Premium") { PremiumView() }
                }
            }
        }
        .navigationTitle("Statistiche")
    }
}
