import SwiftUI

struct HomeView: View {
    @Environment(DataStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(NotificationManager.self) private var notifications

    var body: some View {
        let now = Date()
        let summary = Statistics.summary(store.purchases.filter { !$0.isArchived }, now: now, calendar: store.calendar)
        let attention = store.attentionItems(now: now)
        let overdue = attention.filter { (store.daysRemaining($0, now: now) ?? 1) < 0 && $0.status.deadlineMatters }
        let upcoming = attention.filter { !overdue.contains($0) && $0.status.deadlineMatters }
        let refunds = attention.filter { !$0.status.deadlineMatters }
        let unverified = store.purchases.filter { !$0.isArchived && $0.status.deadlineMatters && ($0.deadline == nil || $0.deadline?.verification == .proposed) }.count

        ZStack(alignment: .bottomTrailing) {
            List {
                if !notifications.isEnabled {
                    Section {
                        NotificationBanner()
                    }
                }

                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        SummaryCard(title: "Da restituire", value: Formatters.money(summary.returnableValue, currency: store.settings.currency), symbol: "arrow.uturn.backward")
                        SummaryCard(title: "Rimborsi in attesa", value: Formatters.money(summary.refundsExpected, currency: store.settings.currency), symbol: "hourglass", tint: .orange)
                        SummaryCard(title: "Da verificare", value: "\(unverified)", symbol: "checkmark.shield", tint: unverified > 0 ? .orange : .green)
                        SummaryCard(title: "Scaduti", value: "\(summary.missedDeadlines)", symbol: "exclamationmark.octagon", tint: summary.missedDeadlines > 0 ? .red : .secondary)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if attention.isEmpty {
                    Section {
                        EmptyStateView(
                            title: store.purchases.isEmpty ? "Nessun acquisto" : "Tutto sotto controllo",
                            message: store.purchases.isEmpty ? "Aggiungi il tuo primo acquisto con il pulsante +." : "Nessuna scadenza richiede attenzione.",
                            symbol: store.purchases.isEmpty ? "bag" : "checkmark.circle"
                        )
                    }
                }

                if !upcoming.isEmpty {
                    Section("Scadenze imminenti e da verificare") {
                        ForEach(upcoming) { p in
                            NavigationLink(value: PurchaseRoute(id: p.id)) { PurchaseRow(purchase: p) }
                        }
                    }
                }
                if !overdue.isEmpty {
                    Section("Scaduti") {
                        ForEach(overdue) { p in
                            NavigationLink(value: PurchaseRoute(id: p.id)) { PurchaseRow(purchase: p) }
                        }
                    }
                }
                if !refunds.isEmpty {
                    Section("Resi spediti e rimborsi in attesa") {
                        ForEach(refunds) { p in
                            NavigationLink(value: PurchaseRoute(id: p.id)) { PurchaseRow(purchase: p) }
                        }
                    }
                }
                Color.clear.frame(height: 70).listRowBackground(Color.clear)
            }
            .listStyle(.insetGrouped)

            Button {
                router.showAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.accentColor, in: Circle())
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            }
            .padding(20)
            .accessibilityLabel("Aggiungi acquisto")
        }
        .navigationTitle(greeting)
    }

    private var greeting: String {
        if let name = store.data.profile?.name.split(separator: " ").first, !name.isEmpty { return "Ciao, \(name)" }
        return "ReturnMate"
    }
}

struct NotificationBanner: View {
    @Environment(NotificationManager.self) private var notifications
    @Environment(DataStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notifiche disattivate", systemImage: "bell.slash.fill")
                .font(.headline).foregroundStyle(.orange)
            Text("Senza notifiche non riceverai i promemoria prima delle scadenze di reso.")
                .font(.footnote).foregroundStyle(.secondary)
            Button(notifications.status == .notDetermined ? "Attiva notifiche" : "Apri Impostazioni") {
                if notifications.status == .notDetermined {
                    Task { await notifications.requestAuthorization(); store.rescheduleReminders() }
                } else if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}
