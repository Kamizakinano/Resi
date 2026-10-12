import SwiftUI

/// Modifica dei dati di un acquisto esistente.
struct PurchaseEditView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var p: Purchase
    @State private var errors: [ValidationIssue] = []

    init(purchase: Purchase) { _p = State(initialValue: purchase) }

    var body: some View {
        let tz = store.settings.timeZone
        let issues = PurchaseValidator.validate(p)
        Form {
            Section("Prodotto") {
                TextField("Nome del prodotto", text: $p.productName)
                HStack { Text("Prezzo unitario"); DecimalField(title: "0,00", value: $p.price) }
                Stepper("Quantità: \(p.quantity)", value: $p.quantity, in: 1...99)
                CurrencyPicker(code: $p.currency)
                TextField("Link al prodotto", text: $p.productURL)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section("Ordine") {
                TextField("Negozio", text: $p.store)
                Picker("Canale", selection: $p.channel) {
                    ForEach(PurchaseChannel.allCases) { Text($0.title).tag($0) }
                }
                CountryPicker(code: $p.storeCountry)
                TextField("Numero d'ordine", text: $p.orderNumber)
                OptionalDatePicker(title: "Data dell'ordine", date: $p.orderDate, timeZone: tz)
                OptionalDatePicker(title: "Data di consegna", date: $p.deliveryDate, timeZone: tz)
                TextField("Link all'ordine", text: $p.orderURL)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            if !issues.isEmpty {
                Section("Verifica dei dati") {
                    ForEach(issues) { i in
                        Label(i.message, systemImage: i.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
                            .foregroundStyle(i.severity == .error ? .red : .orange).font(.footnote)
                    }
                }
            }
            if p.deadline?.manuallyEdited == true {
                Section {
                    Text("La scadenza è stata inserita manualmente e non verrà ricalcolata automaticamente.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Modifica")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") {
                    p.productURL = p.productURL.isEmpty ? "" : PurchaseValidator.normalizedURL(p.productURL)
                    p.orderURL = p.orderURL.isEmpty ? "" : PurchaseValidator.normalizedURL(p.orderURL)
                    errors = store.update(p)
                    if errors.isEmpty { dismiss() }
                }
                .disabled(issues.contains { $0.severity == .error })
            }
        }
    }
}

/// Inserimento o modifica manuale della scadenza.
struct DeadlineEditorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let purchase: Purchase

    @State private var mode: Mode = .days
    @State private var days: Int = 30
    @State private var startEvent: StartEvent = .delivery
    @State private var date: Date = Date()
    @State private var kind: PolicyKind = .storePolicy
    @State private var rule: String = ""
    @State private var sourceURL: String = ""
    @State private var official = false

    enum Mode: String, CaseIterable, Identifiable {
        case days, date
        var id: String { rawValue }
        var title: String { self == .days ? "Numero di giorni" : "Data precisa" }
    }

    private var computed: Date? {
        let start = startEvent == .delivery ? purchase.deliveryDate : purchase.orderDate
        guard let start else { return nil }
        return DeadlineEngine.computeDate(start: start, days: days, kind: kind, calendar: store.calendar).date
    }

    var body: some View {
        let tz = store.settings.timeZone
        Form {
            Section {
                Picker("Modalità", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Tipo", selection: $kind) {
                    Text(PolicyKind.storePolicy.title).tag(PolicyKind.storePolicy)
                    Text(PolicyKind.legalWithdrawal.title).tag(PolicyKind.legalWithdrawal)
                    Text(PolicyKind.manual.title).tag(PolicyKind.manual)
                }
            }
            if mode == .days {
                Section {
                    Stepper("\(days) giorni", value: $days, in: 1...365)
                    Picker("A partire", selection: $startEvent) {
                        ForEach(StartEvent.allCases) { Text($0.title).tag($0) }
                    }
                    if let computed {
                        LabeledContent("Ultimo giorno", value: Formatters.date(computed, timeZone: tz))
                    } else {
                        Text("Manca la data \(startEvent == .delivery ? "di consegna" : "dell'ordine"): aggiungila nei dati dell'acquisto.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                } header: { Text("Regola") }
            } else {
                Section("Data") {
                    DatePicker("Ultimo giorno utile", selection: $date, displayedComponents: .date)
                        .environment(\.timeZone, tz)
                }
            }
            Section {
                TextField("Descrizione della regola (es. 30 giorni dalla consegna)", text: $rule, axis: .vertical)
                TextField("Link alla fonte (facoltativo)", text: $sourceURL)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("La fonte è ufficiale (sito del negozio o norma)", isOn: $official)
                    .disabled(sourceURL.isEmpty)
            } header: {
                Text("Fonte")
            } footer: {
                Text("La scadenza resta \"proposta\" finché non viene verificata. Per verificarla servono una fonte ufficiale e una regola in giorni coerente con le date dell'acquisto.")
            }
        }
        .navigationTitle("Scadenza")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") {
                    let finalDate = mode == .days ? (computed ?? date) : date
                    store.setManualDeadline(purchase.id, date: finalDate, days: mode == .days ? days : nil,
                                            startEvent: startEvent, kind: kind, rule: rule,
                                            sourceURL: sourceURL, sourceIsOfficial: official)
                    dismiss()
                }
                .disabled(mode == .days && computed == nil)
            }
        }
        .onAppear {
            if let d = purchase.deadline {
                date = d.date
                days = d.days ?? 30
                startEvent = d.startEvent
                kind = d.kind == .warranty ? .manual : d.kind
                rule = d.rule
                sourceURL = d.source?.url ?? ""
                official = d.source?.isOfficial ?? false
                mode = d.days == nil ? .date : .days
            }
        }
    }
}

struct ReturnInfoForm: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let purchase: Purchase
    @State private var info = ReturnInfo()

    var body: some View {
        let tz = store.settings.timeZone
        Form {
            Section("Richiesta") {
                OptionalDatePicker(title: "Data della richiesta", date: $info.requestDate, timeZone: tz)
                TextField("Riferimento reso (RMA)", text: $info.reference)
            }
            Section {
                TextField("Corriere", text: $info.carrier)
                TextField("Numero di tracking", text: $info.trackingNumber)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                OptionalDatePicker(title: "Consegnato al corriere il", date: $info.shippedDate, timeZone: tz)
            } header: {
                Text("Spedizione")
            } footer: {
                Text("La consegna al corriere non equivale al rimborso: il rimborso va confermato a parte.")
            }
            Section("Note") {
                TextField("Note sul reso", text: $info.notes, axis: .vertical)
            }
        }
        .navigationTitle("Dati del reso")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") {
                    store.mutate(purchase.id) { p in
                        p.returnInfo = info
                        p.log(.status, "Dati del reso aggiornati" + (info.trackingNumber.isEmpty ? "" : " (tracking \(info.trackingNumber))"))
                    }
                    dismiss()
                }
            }
        }
        .onAppear { info = purchase.returnInfo }
    }
}

struct RefundForm: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let purchase: Purchase
    @State private var expected: Decimal?
    @State private var received: Decimal?
    @State private var cost: Decimal?
    @State private var date = Date()
    @State private var confirmed = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Previsto") {
                HStack { Text("Importo previsto"); DecimalField(title: "0,00", value: $expected) }
            }
            Section {
                Toggle("Ho ricevuto il rimborso", isOn: $confirmed)
                if confirmed {
                    HStack { Text("Importo ricevuto"); DecimalField(title: "0,00", value: $received) }
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                    HStack { Text("Costi di reso"); DecimalField(title: "0,00", value: $cost) }
                }
            } header: {
                Text("Ricevuto")
            } footer: {
                Text("Il rimborso viene considerato ricevuto solo dopo la tua conferma.")
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Rimborso")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") { save() }
            }
        }
        .onAppear {
            expected = purchase.refund.expectedAmount ?? purchase.totalPrice
            received = purchase.refund.receivedAmount ?? (purchase.refund.expectedAmount ?? purchase.totalPrice)
            cost = purchase.refund.returnCost
            date = purchase.refund.receivedDate ?? Date()
            confirmed = purchase.refund.confirmedByUser
        }
    }

    private func save() {
        if confirmed {
            guard let received, received >= 0 else { error = "Inserisci l'importo ricevuto."; return }
            if let cost, cost < 0 { error = "Il costo non può essere negativo."; return }
        }
        store.mutate(purchase.id) { p in
            p.refund.expectedAmount = expected
            if confirmed, let received {
                ReturnFlow.confirmRefund(&p, amount: received, date: date, returnCost: cost)
                if ReturnFlow.canTransition(from: p.status, to: .refunded) {
                    try? ReturnFlow.apply(.refunded, to: &p)
                }
            } else if p.refund.confirmedByUser {
                p.refund.confirmedByUser = false
                p.refund.receivedAmount = nil
                p.refund.receivedDate = nil
                p.log(.refund, "Conferma del rimborso rimossa")
            }
        }
        dismiss()
    }
}

struct NotesEditor: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let purchase: Purchase
    @State private var text = ""

    var body: some View {
        Form {
            TextEditor(text: $text).frame(minHeight: 200)
        }
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") {
                    store.mutate(purchase.id) { p in
                        p.notes = text
                        p.log(.note, "Note aggiornate")
                    }
                    dismiss()
                }
            }
        }
        .onAppear { text = purchase.notes }
    }
}
