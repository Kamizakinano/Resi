import SwiftUI
import PhotosUI

struct AddPurchaseView: View {
    @Environment(DataStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var screenshotItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showText = false
    @State private var showLink = false
    @State private var emailText = ""
    @State private var link = ""
    @State private var useAI = true
    @State private var processing: String?
    @State private var draft: ExtractionDraft?
    @State private var images: [UIImage] = []
    @State private var goConfirm = false

    private var aiConfigured: Bool { Keychain.get(ClaudeClient.keychainKey) != nil }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        var d = ExtractionDraft()
                        d.currency = store.settings.currency
                        d.storeCountry = store.settings.defaultCountry
                        d.source = .manual
                        images = []
                        draft = d
                        goConfirm = true
                    } label: {
                        MethodRow(title: "Inserimento manuale", subtitle: "Compila i campi a mano", symbol: "square.and.pencil")
                    }
                    PhotosPicker(selection: $screenshotItems, maxSelectionCount: 4, matching: .screenshots) {
                        MethodRow(title: "Screenshot", subtitle: "Conferma d'ordine, app del negozio", symbol: "iphone")
                    }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
                        MethodRow(title: "Foto dalla libreria", subtitle: "Ricevuta, scontrino, etichetta", symbol: "photo.on.rectangle")
                    }
                    Button { showCamera = true } label: {
                        MethodRow(title: "Scatta una foto", subtitle: "Fotografa scontrino o ricevuta", symbol: "camera")
                    }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    Button { showText = true } label: {
                        MethodRow(title: "Testo di un'email", subtitle: "Incolla la conferma d'ordine", symbol: "envelope.open")
                    }
                    Button { showLink = true } label: {
                        MethodRow(title: "Link", subtitle: "Pagina del prodotto o dell'ordine", symbol: "link")
                    }
                } header: {
                    Text("Come vuoi aggiungerlo?")
                }

                Section {
                    Toggle("Usa l'AI per estrarre i dati", isOn: $useAI)
                        .disabled(!aiConfigured)
                } footer: {
                    if aiConfigured {
                        Text("Scansioni AI rimaste questo mese: \(store.aiScansRemaining). Senza AI i dati vengono letti sul dispositivo. Prima del salvataggio potrai sempre controllarli e correggerli.")
                    } else {
                        Text("AI non configurata: i dati vengono letti sul dispositivo (testo riconosciuto con OCR). Puoi aggiungere una chiave API in Impostazioni › Intelligenza artificiale.")
                    }
                }
            }
            .navigationTitle("Nuovo acquisto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
            .overlay {
                if let processing {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(processing).font(.callout)
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .onChange(of: photoItems) { _, items in loadImages(items, source: .photo) }
            .onChange(of: screenshotItems) { _, items in loadImages(items, source: .screenshot) }
            .sheet(isPresented: $showCamera) {
                CameraPicker { image in
                    images = [image]
                    run(.images([image], .photo))
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showText) {
                NavigationStack {
                    Form {
                        Section {
                            TextEditor(text: $emailText).frame(minHeight: 240)
                        } footer: {
                            Text("Incolla il testo dell'email di conferma o di spedizione.")
                        }
                    }
                    .navigationTitle("Testo email")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Annulla") { showText = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Analizza") {
                                showText = false
                                images = []
                                run(.text(emailText))
                            }
                            .disabled(emailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .alert("Incolla il link", isPresented: $showLink) {
                TextField("https://…", text: $link)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                Button("Annulla", role: .cancel) {}
                Button("Analizza") {
                    images = []
                    run(.link(link))
                }
            }
            .navigationDestination(isPresented: $goConfirm) {
                if let draft {
                    ConfirmPurchaseView(draft: draft, images: images) { dismiss() }
                }
            }
            .onAppear {
                if router.launchScreen == "confirm", draft == nil {
                    draft = DemoData.sampleDraft
                    goConfirm = true
                }
            }
        }
    }

    private func loadImages(_ items: [PhotosPickerItem], source: InputSource) {
        guard !items.isEmpty else { return }
        processing = "Caricamento immagini…"
        Task {
            var loaded: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    loaded.append(image)
                }
            }
            photoItems = []
            screenshotItems = []
            guard !loaded.isEmpty else {
                processing = nil
                var d = ExtractionDraft()
                d.warnings = ["Impossibile leggere le immagini selezionate."]
                draft = d
                goConfirm = true
                return
            }
            images = loaded
            run(.images(loaded, source))
        }
    }

    private func run(_ input: ImportInput) {
        processing = useAI && aiConfigured ? "Analisi con l'AI…" : "Lettura del testo…"
        Task {
            let result = await ImportService.process(input, store: store, useAI: useAI && aiConfigured)
            processing = nil
            draft = result
            goConfirm = true
        }
    }
}

struct MethodRow: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading) {
                Text(title).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
