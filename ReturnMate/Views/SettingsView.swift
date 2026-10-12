import SwiftUI

struct SettingsView: View {
    @Environment(DataStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(NotificationManager.self) private var notifications
    @Environment(PremiumManager.self) private var premium
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var confirmDeleteAccount = false
    @State private var showProfile = false
    @State private var goPremium = false

    var body: some View {
        let settings = store.settings
        Form {
            Section {
                Button { showProfile = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 40)).foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading) {
                            Text(store.data.profile?.name ?? "—").font(.headline).foregroundStyle(.primary)
                            Text(store.data.profile?.email.nilIfEmpty ?? "Account locale").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                NavigationLink { PremiumView() } label: {
                    Label(premium.isPremium ? "Premium attivo" : "Passa a Premium", systemImage: "star.fill")
                }
            }

            Section("Preferenze") {
                CurrencyPicker(code: Binding(get: { settings.currency }, set: { v in store.updateSettings { $0.currency = v } }))
                CountryPicker(code: Binding(get: { settings.defaultCountry }, set: { v in store.updateSettings { $0.defaultCountry = v } }))
                NavigationLink {
                    TimeZonePicker(selection: Binding(get: { settings.timeZoneID }, set: { v in store.updateSettings { $0.timeZoneID = v } }))
                } label: {
                    LabeledContent("Fuso orario", value: settings.timeZoneID)
                }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    LabeledContent("Lingua", value: "Italiano")
                }
            }

            Section {
                NavigationLink { NotificationSettingsView() } label: {
                    LabeledContent("Promemoria", value: notifications.isEnabled ? "\(notifications.pendingCount) pianificati" : "Disattivati")
                }
            } header: {
                Text("Notifiche")
            } footer: {
                if !notifications.isEnabled {
                    Text("Le notifiche sono disattivate: non riceverai promemoria.").foregroundStyle(.orange)
                }
            }

            Section {
                NavigationLink { AISettingsView() } label: {
                    LabeledContent("Intelligenza artificiale", value: Keychain.get(ClaudeClient.keychainKey) == nil ? "Non configurata" : "Attiva")
                }
            }

            Section {
                Toggle("Blocca con Face ID / codice", isOn: Binding(get: { settings.appLock }, set: { v in store.updateSettings { $0.appLock = v } }))
            } header: {
                Text("Sicurezza")
            } footer: {
                Text("I dati sono salvati solo su questo iPhone con la protezione dei dati di iOS: sono cifrati quando il telefono è bloccato.")
            }

            Section {
                Button { export(csv: true) } label: { Label("Esporta CSV", systemImage: "tablecells") }
                Button { export(csv: false) } label: { Label("Esporta PDF", systemImage: "doc.richtext") }
                if let exportError { Text(exportError).foregroundStyle(.red).font(.footnote) }
            } header: {
                Text("Esportazione")
            } footer: {
                if !premium.isPremium { Text("L'esportazione fa parte di Premium.") }
            }

            Section("Informazioni") {
                NavigationLink("Informativa sulla privacy") { LegalView(page: .privacy) }
                NavigationLink("Condizioni d'uso") { LegalView(page: .terms) }
                NavigationLink("Conservazione dei dati") { LegalView(page: .retention) }
                LabeledContent("Versione", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            }

            Section {
                Button("Elimina account e tutti i dati", role: .destructive) { confirmDeleteAccount = true }
            }
        }
        .navigationTitle("Impostazioni")
        .navigationDestination(isPresented: $goPremium) { PremiumView() }
        .sheet(item: $exportURL) { url in
            ShareSheet(items: [url])
        }
        .sheet(isPresented: $showProfile) {
            NavigationStack { ProfileEditView() }
        }
        .confirmationDialog("Eliminare l'account?", isPresented: $confirmDeleteAccount, titleVisibility: .visible) {
            Button("Elimina tutto", role: .destructive) { store.deleteAccount() }
        } message: {
            Text("Verranno eliminati definitivamente profilo, acquisti, allegati, impostazioni e chiave API.")
        }
        .onAppear {
            if router.launchScreen == "premium" { router.launchScreen = nil; goPremium = true }
        }
    }

    private func export(csv: Bool) {
        guard premium.isPremium else { goPremium = true; return }
        do {
            let tz = store.settings.timeZone
            if csv {
                exportURL = try Exporter.writeCSV(store.purchases, timeZone: tz)
            } else {
                let summary = Statistics.summary(store.purchases, now: Date(), calendar: store.calendar)
                exportURL = try Exporter.writePDF(store.purchases, summary: summary, currency: store.settings.currency, timeZone: tz)
            }
            exportError = nil
        } catch {
            exportError = "Esportazione non riuscita: \(error.localizedDescription)"
        }
    }
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ProfileEditView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""

    var body: some View {
        Form {
            Section {
                TextField("Nome", text: $name)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            } footer: {
                Text("Profilo locale creato il \(Formatters.date(store.data.profile?.createdAt)).")
            }
        }
        .navigationTitle("Profilo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") {
                    store.data.profile?.name = name.trimmingCharacters(in: .whitespaces)
                    store.data.profile?.email = email.trimmingCharacters(in: .whitespaces)
                    store.save()
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            name = store.data.profile?.name ?? ""
            email = store.data.profile?.email ?? ""
        }
    }
}

struct TimeZonePicker: View {
    @Binding var selection: String
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let ids = TimeZone.knownTimeZoneIdentifiers.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
        List(ids, id: \.self) { id in
            Button {
                selection = id
                dismiss()
            } label: {
                HStack {
                    Text(id).foregroundStyle(.primary)
                    Spacer()
                    if id == selection { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle("Fuso orario")
    }
}

struct NotificationSettingsView: View {
    @Environment(DataStore.self) private var store
    @Environment(NotificationManager.self) private var notifications
    @State private var customDays = 14

    private let presets = [14, 7, 3, 2, 1, 0]

    private var offsets: [Int] {
        Array(Set(presets + store.settings.reminderOffsets)).sorted(by: >)
    }

    private func label(for d: Int) -> String {
        switch d {
        case 0: return "Il giorno della scadenza"
        case 1: return "1 giorno prima"
        default: return "\(d) giorni prima"
        }
    }

    private func setOffset(_ d: Int, on: Bool) {
        store.updateSettings { s in
            var set = Set(s.reminderOffsets)
            if on { set.insert(d) } else { set.remove(d) }
            s.reminderOffsets = set.sorted(by: >)
        }
    }

    private func binding(for d: Int) -> Binding<Bool> {
        Binding(get: { store.settings.reminderOffsets.contains(d) }, set: { setOffset(d, on: $0) })
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                let s = store.settings
                return Calendar.current.date(bySettingHour: s.reminderHour, minute: s.reminderMinute, second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                store.updateSettings { s in
                    s.reminderHour = c.hour ?? 9
                    s.reminderMinute = c.minute ?? 0
                }
            }
        )
    }

    var body: some View {
        let settings = store.settings
        Form {
            if !notifications.isEnabled {
                Section { NotificationBanner() }
            }
            Section {
                ForEach(offsets, id: \.self) { d in
                    Toggle(label(for: d), isOn: binding(for: d))
                }
                Stepper("Altro intervallo: \(customDays) giorni", value: $customDays, in: 1...60)
                Button("Aggiungi \(customDays) giorni prima") { setOffset(customDays, on: true) }
            } header: {
                Text("Quando avvisarmi")
            }
            Section("Orario") {
                DatePicker("Ora dei promemoria", selection: timeBinding, displayedComponents: .hourAndMinute)
            }
            Section {
                Toggle("Avvisi per scadenze da verificare", isOn: Binding(get: { settings.verifyReminders }, set: { v in store.updateSettings { $0.verifyReminders = v } }))
            } footer: {
                Text("I promemoria vengono pianificati da iOS e arrivano anche ad app chiusa. Si interrompono automaticamente quando decidi di tenere il prodotto, spedisci il reso o lo chiudi. Ogni modifica aggiorna quelli esistenti senza duplicarli.")
            }
        }
        .navigationTitle("Promemoria")
        .task { await notifications.refreshStatus() }
    }
}

struct AISettingsView: View {
    @Environment(DataStore.self) private var store
    @State private var key = ""
    @State private var hasKey = false
    @State private var testing = false
    @State private var result: String?

    static let models = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]

    var body: some View {
        Form {
            Section {
                if hasKey {
                    LabeledContent("Chiave API", value: "Salvata nel Portachiavi")
                    Button("Rimuovi chiave", role: .destructive) {
                        Keychain.set(nil, for: ClaudeClient.keychainKey)
                        hasKey = false
                    }
                } else {
                    SecureField("sk-ant-…", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Salva chiave") {
                        Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: ClaudeClient.keychainKey)
                        key = ""
                        hasKey = true
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Chiave API Anthropic")
            } footer: {
                Text("L'AI legge screenshot, foto ed email e cerca online le politiche di reso. Crea una chiave su console.anthropic.com: l'uso viene addebitato sul tuo account Anthropic. La chiave resta cifrata nel Portachiavi di questo iPhone.")
            }
            Section("Modello") {
                Picker("Modello", selection: Binding(get: { store.settings.aiModel }, set: { v in store.updateSettings { $0.aiModel = v } })) {
                    ForEach(Self.models, id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("Scansioni rimaste questo mese", value: "\(store.aiScansRemaining)")
            }
            Section {
                Button {
                    testing = true
                    result = nil
                    Task {
                        defer { testing = false }
                        guard let client = ClaudeClient.fromKeychain(model: store.settings.aiModel) else {
                            result = AIError.missingKey.localizedDescription
                            return
                        }
                        do {
                            try await client.ping()
                            result = "Connessione riuscita."
                        } catch {
                            result = error.localizedDescription
                        }
                    }
                } label: {
                    if testing { ProgressView() } else { Text("Prova la connessione") }
                }
                .disabled(!hasKey || testing)
                if let result { Text(result).font(.footnote) }
            } footer: {
                Text("Se l'AI non è disponibile puoi sempre inserire i dati a mano o usare la lettura del testo sul dispositivo.")
            }
        }
        .navigationTitle("Intelligenza artificiale")
        .onAppear { hasKey = Keychain.get(ClaudeClient.keychainKey) != nil }
    }
}
