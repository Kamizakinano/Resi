import SwiftUI
import StoreKit

struct PremiumView: View {
    @Environment(PremiumManager.self) private var premium
    @Environment(\.openURL) private var openURL
    @State private var message: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "star.circle.fill").font(.system(size: 48)).foregroundStyle(.yellow)
                    Text("ReturnMate Premium").font(.title2.bold())
                    Text("Le funzioni essenziali per gestire scadenze e resi restano sempre gratuite.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            Section("Gratis") {
                Feature(text: "Acquisti, scadenze, promemoria e gestione dei resi illimitati")
                Feature(text: "Calendario, ricerca e archivio")
                Feature(text: "10 scansioni AI al mese")
            }
            Section("Premium") {
                Feature(text: "Fino a 200 scansioni AI al mese", premium: true)
                Feature(text: "Statistiche avanzate per negozio e periodo", premium: true)
                Feature(text: "Esportazione CSV e PDF", premium: true)
            }

            if PremiumManager.sideloadUnlock {
                Section {
                    Label("Versione di prova: le funzioni Premium sono sbloccate.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } footer: {
                    Text("Le app installate con sideload non possono effettuare acquisti tramite App Store.")
                }
            }

            Section {
                if premium.isLoading {
                    ProgressView()
                } else if premium.products.isEmpty {
                    Text(premium.loadError ?? "Abbonamenti non disponibili.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(premium.products, id: \.id) { product in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(product.displayName).font(.headline)
                                Spacer()
                                Text(product.displayPrice).font(.headline)
                            }
                            if let sub = product.subscription {
                                Text("Fatturazione: ogni \(periodText(sub.subscriptionPeriod)). Rinnovo automatico, annullabile in qualsiasi momento fino a 24 ore prima del rinnovo.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Button(premium.purchasedIDs.contains(product.id) ? "Attivo" : "Abbonati") {
                                Task { message = await premium.purchase(product) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(premium.purchasedIDs.contains(product.id))
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Piani")
            }

            Section {
                Button("Ripristina acquisti") { Task { message = await premium.restore() } }
                Button("Gestisci o annulla abbonamento") {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") { openURL(url) }
                }
            }
            if let message { Section { Text(message).font(.footnote) } }
        }
        .navigationTitle("Premium")
        .task { await premium.load() }
    }

    private func periodText(_ p: Product.SubscriptionPeriod) -> String {
        switch p.unit {
        case .day: return p.value == 1 ? "giorno" : "\(p.value) giorni"
        case .week: return p.value == 1 ? "settimana" : "\(p.value) settimane"
        case .month: return p.value == 1 ? "mese" : "\(p.value) mesi"
        case .year: return p.value == 1 ? "anno" : "\(p.value) anni"
        @unknown default: return "periodo"
        }
    }
}

private struct Feature: View {
    let text: String
    var premium = false
    var body: some View {
        Label(text, systemImage: premium ? "star.fill" : "checkmark")
            .foregroundStyle(.primary)
            .symbolRenderingMode(.multicolor)
    }
}
