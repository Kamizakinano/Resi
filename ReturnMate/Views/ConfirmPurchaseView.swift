import SwiftUI

struct ConfirmPurchaseView: View {
    @Environment(DataStore.self) private var store
    @State private var draft: ExtractionDraft
    let images: [UIImage]
    let onSaved: () -> Void
    @State private var saveErrors: [ValidationIssue] = []
    @State private var saving = false

    init(draft: ExtractionDraft, images: [UIImage], onSaved: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.images = images
        self.onSaved = onSaved
    }

    private var preview: [Purchase] { draft.makePurchases(receipt: nil, productPhoto: nil) }

    private var issues: [ValidationIssue] {
        var seen = Set<String>()
        return preview.flatMap { PurchaseValidator.validate($0) }.filter { seen.insert($0.message).inserted }
    }

    var body: some View {
        let tz = store.settings.timeZone
        Form {
            if !draft.warnings.isEmpty {
                Section {
                    WarningList(warnings: draft.warnings)
                } header: {
                    Text(draft.usedAI ? "Controlla i dati estratti dall'AI" : "Controlla i dati estratti")
                }
            }

            if !images.isEmpty {
                Section("Immagini") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Array(images.enumerated()), id: \.offset) { _, img in
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(width: 90, height: 120).clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    Text("Le immagini verranno salvate come ricevuta dell'acquisto.").font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Ordine") {
                TextField("Negozio (obbligatorio)", text: $draft.store)
                Picker("Canale", selection: $draft.channel) {
                    ForEach(PurchaseChannel.allCases) { Text($0.title).tag($0) }
                }
                CountryPicker(code: $draft.storeCountry)
                TextField("Numero d'ordine", text: $draft.orderNumber)
                    .textInputAutocapitalization(.characters)
                OptionalDatePicker(title: "Data dell'ordine", date: $draft.orderDate, timeZone: tz)
                OptionalDatePicker(title: "Data di consegna", date: $draft.deliveryDate, timeZone: tz)
                CurrencyPicker(code: $draft.currency)
                TextField("Link all'ordine", text: $draft.orderURL)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            }

            ForEach($draft.items) { $item in
                Section {
                    TextField("Nome del prodotto (obbligatorio)", text: $item.name)
                    HStack {
                        Text("Prezzo unitario")
                        DecimalField(title: "0,00", value: $item.price)
                    }
                    Stepper("Quantità: \(item.quantity)", value: $item.quantity, in: 1...99)
                    TextField("Link al prodotto", text: $item.productURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if draft.items.count > 1 {
                        Button("Rimuovi prodotto", role: .destructive) {
                            draft.items.removeAll { $0.id == item.id }
                        }
                    }
                } header: {
                    Text(draft.items.count > 1 ? "Prodotto \((draft.items.firstIndex(where: { $0.id == item.id }) ?? 0) + 1)" : "Prodotto")
                }
            }

            Section {
                Button {
                    draft.items.append(ExtractedItem())
                } label: {
                    Label("Aggiungi un altro prodotto dello stesso ordine", systemImage: "plus.circle")
                }
            }

            if !issues.isEmpty {
                Section("Verifica dei dati") {
                    ForEach(issues) { issue in
                        Label(issue.message, systemImage: issue.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
                            .foregroundStyle(issue.severity == .error ? .red : .orange)
                            .font(.footnote)
                    }
                }
            }
        }
        .navigationTitle("Conferma dati")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") { save() }
                    .bold()
                    .disabled(saving || issues.contains { $0.severity == .error })
            }
        }
    }

    private func save() {
        saving = true
        var receipt: Attachment?
        if let first = images.first {
            receipt = try? AttachmentStore.saveImage(first, kind: draft.source == .screenshot ? .screenshot : .receipt)
        }
        var purchases = draft.makePurchases(receipt: receipt, productPhoto: nil)
        // Le immagini aggiuntive vengono allegate al primo prodotto.
        for extra in images.dropFirst() {
            if let att = try? AttachmentStore.saveImage(extra, kind: .receipt), !purchases.isEmpty {
                purchases[0].attachments.append(att)
            }
        }
        if !draft.warnings.isEmpty {
            for i in purchases.indices {
                purchases[i].log(.note, "Avvisi in fase di importazione: " + draft.warnings.joined(separator: " · "))
            }
        }
        let errors = store.add(purchases)
        if !errors.isEmpty {
            saveErrors = errors
            saving = false
            return
        }
        // Ricerca automatica della politica di reso se non è già in archivio.
        if let first = purchases.first,
           store.data.policyCache[store.policyKey(store: first.store, country: first.storeCountry)] == nil,
           Keychain.get(ClaudeClient.keychainKey) != nil {
            Task { _ = await PolicyService.research(for: first.id, store: store) }
        }
        onSaved()
    }
}

struct CountryPicker: View {
    @Binding var code: String
    static let common = ["IT", "DE", "FR", "ES", "NL", "BE", "AT", "IE", "PT", "PL", "SE", "DK", "FI", "GB", "CH", "US", "CN"]

    var body: some View {
        Picker("Paese del negozio", selection: $code) {
            ForEach(options, id: \.self) { c in
                Text("\(Locale(identifier: "it_IT").localizedString(forRegionCode: c) ?? c) (\(c))").tag(c)
            }
        }
    }

    private var options: [String] {
        Self.common.contains(code.uppercased()) || code.isEmpty ? Self.common : [code.uppercased()] + Self.common
    }
}

struct CurrencyPicker: View {
    @Binding var code: String
    static let common = ["EUR", "USD", "GBP", "CHF", "SEK", "DKK", "PLN", "CZK", "JPY", "CNY"]

    var body: some View {
        Picker("Valuta", selection: $code) {
            ForEach(options, id: \.self) { Text($0).tag($0) }
        }
    }

    private var options: [String] {
        Self.common.contains(code.uppercased()) ? Self.common : [code.uppercased()] + Self.common
    }
}
