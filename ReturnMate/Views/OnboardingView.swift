import SwiftUI

struct OnboardingView: View {
    @Environment(DataStore.self) private var store
    @State private var name = ""
    @State private var email = ""
    @State private var acceptedTerms = false
    @State private var showPrivacy = false

    private var emailValid: Bool {
        email.isEmpty || email.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 52)).foregroundStyle(Color.accentColor)
                        Text("Benvenuto in ReturnMate").font(.title.bold())
                        Text("Tieni traccia degli acquisti, delle scadenze di reso e dei rimborsi.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                Section {
                    TextField("Nome", text: $name)
                        .textContentType(.name)
                    TextField("Email (facoltativa)", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !emailValid {
                        Text("Indirizzo email non valido.").font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Il tuo profilo")
                } footer: {
                    Text("L'account è salvato solo su questo iPhone, in forma cifrata. L'accesso con Apple/Google e la sincronizzazione tra dispositivi richiedono un server e la distribuzione su App Store: non sono disponibili in questa versione installata con sideload.")
                }
                Section {
                    Toggle("Accetto le condizioni d'uso e l'informativa privacy", isOn: $acceptedTerms)
                    Button("Leggi informativa e condizioni") { showPrivacy = true }
                }
                Section {
                    Button {
                        store.createProfile(name: name, email: email)
                        Task { await NotificationManager.shared.requestAuthorization(); store.rescheduleReminders() }
                    } label: {
                        Text("Crea account").frame(maxWidth: .infinity).bold()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !emailValid || !acceptedTerms)
                }
            }
            .sheet(isPresented: $showPrivacy) {
                NavigationStack { LegalView(page: .privacy) }
            }
        }
    }
}
