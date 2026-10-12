import SwiftUI
import PhotosUI

struct PurchaseDetailView: View {
    @Environment(DataStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let id: UUID

    @State private var showEdit = false
    @State private var showDeadlineEditor = false
    @State private var showStatusPicker = false
    @State private var showReturnInfo = false
    @State private var showRefund = false
    @State private var confirmDelete = false
    @State private var message: String?
    @State private var verifyIssues: [DeadlineEngine.VerificationIssue] = []
    @State private var newPhotos: [PhotosPickerItem] = []
    @State private var viewing: Attachment?
    @State private var showNotes = false

    var body: some View {
        if let p = store.purchase(id) {
            content(p)
        } else {
            EmptyStateView(title: "Acquisto non trovato", message: "Potrebbe essere stato eliminato.", symbol: "questionmark.folder")
        }
    }

    @ViewBuilder
    private func content(_ p: Purchase) -> some View {
        let tz = store.settings.timeZone
        let days = store.daysRemaining(p)
        List {
            // Intestazione
            Section {
                HStack(alignment: .top, spacing: 14) {
                    ThumbnailView(purchase: p, size: 84)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(p.productName).font(.title3.bold())
                        Text(p.store).foregroundStyle(.secondary)
                        Text(Formatters.money(p.totalPrice, currency: p.currency)).font(.headline)
                        if p.quantity > 1 {
                            Text("\(p.quantity) × \(Formatters.money(p.price, currency: p.currency))").font(.caption).foregroundStyle(.secondary)
                        }
                        StatusChip(status: p.status)
                    }
                }
                .padding(.vertical, 4)
                if p.isArchived {
                    Label("Archiviato", systemImage: "archivebox").foregroundStyle(.secondary)
                }
                let siblings = store.items(inOrder: p.orderGroup).filter { $0.id != p.id }
                if !siblings.isEmpty {
                    DisclosureGroup("Stesso ordine: altri \(siblings.count) prodotti") {
                        ForEach(siblings) { s in
                            NavigationLink(value: PurchaseRoute(id: s.id)) {
                                HStack {
                                    Text(s.productName)
                                    Spacer()
                                    Text(s.status.title).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            deadlineSection(p, days: days, tz: tz)
            policySection(p, tz: tz)
            statusSection(p, tz: tz)
            refundSection(p, tz: tz)

            Section("Dettagli acquisto") {
                LabeledContent("Data ordine", value: Formatters.date(p.orderDate, timeZone: tz))
                LabeledContent("Data consegna", value: Formatters.date(p.deliveryDate, timeZone: tz))
                if !p.orderNumber.isEmpty {
                    LabeledContent("Numero d'ordine") {
                        Text(p.orderNumber).textSelection(.enabled)
                    }
                }
                LabeledContent("Canale", value: p.channel.title)
                LabeledContent("Paese", value: Locale(identifier: "it_IT").localizedString(forRegionCode: p.storeCountry) ?? p.storeCountry)
                LabeledContent("Inserito tramite", value: p.source.title)
                if let w = p.legalWarrantyEnd {
                    LabeledContent("Garanzia legale fino al", value: Formatters.date(w, timeZone: tz))
                }
                if let url = URL(string: p.orderURL), !p.orderURL.isEmpty {
                    Button { openURL(url) } label: { Label("Apri la pagina dell'ordine", systemImage: "safari") }
                }
                if let url = URL(string: p.productURL), !p.productURL.isEmpty {
                    Button { openURL(url) } label: { Label("Apri la pagina del prodotto", systemImage: "link") }
                }
            }

            Section {
                if p.notes.isEmpty {
                    Text("Nessuna nota").foregroundStyle(.secondary)
                } else {
                    Text(p.notes)
                }
                Button(p.notes.isEmpty ? "Aggiungi nota" : "Modifica nota") { showNotes = true }
            } header: { Text("Note") }

            attachmentsSection(p)

            Section("Cronologia") {
                ForEach(p.history.reversed()) { h in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.message).font(.subheadline)
                        Text(Formatters.dateTime(h.date, timeZone: tz)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    store.setArchived(p.id, !p.isArchived)
                } label: {
                    Label(p.isArchived ? "Ripristina dall'archivio" : "Archivia", systemImage: p.isArchived ? "tray.and.arrow.up" : "archivebox")
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Elimina acquisto", systemImage: "trash")
                }
            }
        }
        .navigationTitle(p.productName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Modifica") { showEdit = true } }
        }
        .sheet(isPresented: $showEdit) { NavigationStack { PurchaseEditView(purchase: p) } }
        .sheet(isPresented: $showDeadlineEditor) { NavigationStack { DeadlineEditorView(purchase: p) } }
        .sheet(isPresented: $showReturnInfo) { NavigationStack { ReturnInfoForm(purchase: p) } }
        .sheet(isPresented: $showRefund) { NavigationStack { RefundForm(purchase: p) } }
        .sheet(isPresented: $showNotes) { NavigationStack { NotesEditor(purchase: p) } }
        .sheet(item: $viewing) { att in AttachmentViewer(attachment: att) }
        .confirmationDialog("Cambia stato", isPresented: $showStatusPicker, titleVisibility: .visible) {
            ForEach(ReturnFlow.allowedTargets(from: p.status)) { target in
                Button(target.title) { changeStatus(p, to: target) }
            }
        } message: {
            Text("Puoi saltare gli stati non pertinenti: verranno annotati nella cronologia.")
        }
        .confirmationDialog("Eliminare questo acquisto?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                store.delete(p.id)
                dismiss()
            }
        } message: {
            Text("Verranno eliminati anche allegati e cronologia. L'operazione non è reversibile.")
        }
        .alert("ReturnMate", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .onChange(of: newPhotos) { _, items in
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        store.addAttachment(p.id, image: image, kind: p.imageAttachmentID == nil ? .productPhoto : .document)
                    }
                }
                newPhotos = []
            }
        }
        .onAppear {
            if router.launchScreen == "returnflow" { router.launchScreen = nil; showStatusPicker = true }
        }
    }

    // MARK: - Sezioni

    @ViewBuilder
    private func deadlineSection(_ p: Purchase, days: Int?, tz: TimeZone) -> some View {
        Section {
            if let d = p.deadline {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(p.status.deadlineMatters ? Formatters.daysLabel(days ?? 0) : "Scadenza non più rilevante")
                                .font(.title2.bold())
                                .foregroundStyle(DeadlineTone.of(p, days: days).color)
                            Text("Ultimo giorno: \(Formatters.date(d.date, timeZone: tz))").font(.subheadline)
                        }
                        Spacer()
                        VerificationBadge(state: d.verification)
                    }
                    Text(d.rule).font(.footnote).foregroundStyle(.secondary)
                    if d.manuallyEdited {
                        Label("Data inserita manualmente", systemImage: "pencil").font(.caption).foregroundStyle(.secondary)
                    }
                    if let s = d.source {
                        Button {
                            if let url = URL(string: s.url) { openURL(url) }
                        } label: {
                            Label(s.title, systemImage: "doc.text.magnifyingglass").font(.footnote).lineLimit(2)
                        }
                        .buttonStyle(.borderless)
                        Text("Fonte verificata il \(Formatters.date(s.lastChecked, timeZone: tz))\(s.isOfficial ? " · ufficiale" : " · non ufficiale")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    WarningList(warnings: d.warnings)
                    if d.verification == .proposed {
                        Text("Scadenza proposta: verificala con la fonte prima di farci affidamento.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Label("Scadenza non determinata", systemImage: "calendar.badge.exclamationmark")
                    .font(.headline).foregroundStyle(.orange)
                Text("Non ci sono dati sufficienti per calcolare la scadenza. Inseriscila manualmente o cerca la politica del negozio.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if p.needsManualDeadline && p.deadline != nil {
                Label("Informazioni non sufficienti: conferma o inserisci la scadenza manualmente.", systemImage: "hand.raised")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if !verifyIssues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Impossibile verificare:").font(.footnote.bold())
                    ForEach(verifyIssues, id: \.self) { Text("• " + $0.rawValue).font(.footnote) }
                }
                .foregroundStyle(.red)
            }

            if let d = p.deadline {
                if d.verification == .proposed {
                    Button {
                        verifyIssues = store.verifyDeadline(p.id)
                        if verifyIssues.isEmpty { message = "Scadenza contrassegnata come verificata." }
                    } label: { Label("Ho controllato: segna come verificata", systemImage: "checkmark.shield") }
                } else {
                    Button { store.unverifyDeadline(p.id) } label: { Label("Rimuovi verifica", systemImage: "xmark.shield") }
                }
            }
            Button { showDeadlineEditor = true } label: {
                Label(p.deadline == nil ? "Inserisci scadenza" : "Modifica scadenza", systemImage: "calendar.badge.clock")
            }
            if p.deadline?.manuallyEdited == true {
                Button { store.resetDeadline(p.id) } label: { Label("Torna al calcolo automatico", systemImage: "arrow.counterclockwise") }
            }
            Button {
                Task { message = await PolicyService.research(for: p.id, store: store) }
            } label: {
                if store.researchInProgress.contains(p.id) {
                    HStack { ProgressView(); Text("Ricerca in corso…") }
                } else {
                    Label("Cerca la politica di reso del negozio", systemImage: "magnifyingglass")
                }
            }
            .disabled(store.researchInProgress.contains(p.id))
        } header: {
            Text("Scadenza reso")
        }
    }

    @ViewBuilder
    private func policySection(_ p: Purchase, tz: TimeZone) -> some View {
        let storePolicy = p.policies.first { $0.kind == .storePolicy }
        let legal = p.channel == .online ? DeadlineEngine.legalWithdrawalPolicy(country: p.storeCountry) : nil
        if storePolicy != nil || legal != nil {
            Section("Regole applicabili") {
                if let sp = storePolicy {
                    PolicyBlock(policy: sp, tz: tz)
                }
                if let legal {
                    PolicyBlock(policy: legal, tz: tz)
                }
                if p.channel == .inStore {
                    Text("Per gli acquisti in negozio la legge non prevede il diritto di recesso: vale solo la politica del negozio.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Text("La garanzia legale per prodotti difettosi (2 anni nell'UE) è distinta dal reso e non dipende da queste scadenze.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func statusSection(_ p: Purchase, tz: TimeZone) -> some View {
        Section {
            StatusTimeline(current: p.status)
            if p.status != .closed {
                Button { showStatusPicker = true } label: { Label("Cambia stato", systemImage: "arrow.right.circle") }
            }
            if p.history.last(where: { $0.kind == .status })?.message.hasPrefix("Stato: ") == true {
                Button {
                    store.mutate(p.id) { _ = ReturnFlow.undoLast(&$0) }
                } label: { Label("Annulla ultimo cambio di stato", systemImage: "arrow.uturn.backward") }
            }
            if p.status.isReturnPath || p.status.step >= 3 {
                if let r = p.returnInfo.requestDate { LabeledContent("Richiesta il", value: Formatters.date(r, timeZone: tz)) }
                if !p.returnInfo.reference.isEmpty { LabeledContent("Riferimento reso", value: p.returnInfo.reference) }
                if !p.returnInfo.carrier.isEmpty { LabeledContent("Corriere", value: p.returnInfo.carrier) }
                if !p.returnInfo.trackingNumber.isEmpty {
                    LabeledContent("Tracking") { Text(p.returnInfo.trackingNumber).textSelection(.enabled) }
                }
                if let s = p.returnInfo.shippedDate { LabeledContent("Consegnato al corriere", value: Formatters.date(s, timeZone: tz)) }
                if !p.returnInfo.notes.isEmpty { Text(p.returnInfo.notes).font(.footnote) }
                Button { showReturnInfo = true } label: { Label("Dati del reso", systemImage: "shippingbox") }
            }
        } header: {
            Text("Gestione del reso")
        }
    }

    @ViewBuilder
    private func refundSection(_ p: Purchase, tz: TimeZone) -> some View {
        if p.status.step >= 3 || p.refund.confirmedByUser || p.refund.receivedAmount != nil {
            Section {
                LabeledContent("Importo previsto", value: Formatters.money(p.refund.expectedAmount ?? p.totalPrice, currency: p.currency))
                if p.refund.confirmedByUser {
                    LabeledContent("Ricevuto", value: Formatters.money(p.refund.receivedAmount, currency: p.currency))
                    LabeledContent("Data rimborso", value: Formatters.date(p.refund.receivedDate, timeZone: tz))
                    if let c = p.refund.returnCost, c > 0 {
                        LabeledContent("Costo del reso", value: Formatters.money(c, currency: p.currency))
                    }
                } else {
                    Text("Rimborso non ancora confermato.").font(.footnote).foregroundStyle(.secondary)
                }
                Button { showRefund = true } label: {
                    Label(p.refund.confirmedByUser ? "Modifica rimborso" : "Registra rimborso ricevuto", systemImage: "eurosign.circle")
                }
                if p.status == .refunded {
                    Button {
                        changeStatus(p, to: .closed)
                        store.setArchived(p.id, true)
                    } label: { Label("Chiudi e archivia", systemImage: "archivebox") }
                }
            } header: {
                Text("Rimborso")
            }
        }
    }

    @ViewBuilder
    private func attachmentsSection(_ p: Purchase) -> some View {
        Section("Documenti e foto") {
            if !p.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(p.attachments) { att in
                            Button { viewing = att } label: {
                                VStack {
                                    if let img = AttachmentStore.loadImage(att) {
                                        Image(uiImage: img).resizable().scaledToFill()
                                            .frame(width: 80, height: 100).clipShape(RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        Image(systemName: "doc").font(.largeTitle).frame(width: 80, height: 100)
                                    }
                                    Text(att.kind.title).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { store.removeAttachment(p.id, attachment: att) } label: {
                                    Label("Elimina", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            PhotosPicker(selection: $newPhotos, maxSelectionCount: 5, matching: .images) {
                Label("Aggiungi foto o ricevuta", systemImage: "paperclip")
            }
        }
    }

    private func changeStatus(_ p: Purchase, to target: ReturnStatus) {
        if target == .refunded && !p.refund.confirmedByUser {
            showRefund = true
            return
        }
        do {
            try store.changeStatus(p.id, to: target)
            if [.requested, .shipped].contains(target) { showReturnInfo = true }
        } catch {
            message = error.localizedDescription
        }
    }
}

struct VerificationBadge: View {
    let state: VerificationState
    var body: some View {
        Label(state.title, systemImage: state == .verified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            .font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background((state == .verified ? Color.green : Color.orange).opacity(0.15), in: Capsule())
            .foregroundStyle(state == .verified ? .green : .orange)
    }
}

struct PolicyBlock: View {
    let policy: ReturnPolicy
    let tz: TimeZone
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(policy.kind.title).font(.subheadline.bold())
            if let days = policy.days {
                Text("\(days) giorni \(policy.startEvent.title)").font(.subheadline)
            } else {
                Text("Durata non indicata dalla fonte").font(.subheadline).foregroundStyle(.orange)
            }
            if let free = policy.freeReturn {
                Text(free ? "Reso gratuito" : "Reso a pagamento").font(.caption)
            }
            ForEach(policy.conditions, id: \.self) { Text("• " + $0).font(.caption) }
            if !policy.exclusions.isEmpty {
                Text("Esclusioni").font(.caption.bold()).padding(.top, 2)
                ForEach(policy.exclusions, id: \.self) { Text("• " + $0).font(.caption) }
            }
            if !policy.returnMethods.isEmpty {
                Text("Modalità").font(.caption.bold()).padding(.top, 2)
                ForEach(policy.returnMethods, id: \.self) { Text("• " + $0).font(.caption) }
            }
            if !policy.notes.isEmpty { Text(policy.notes).font(.caption).foregroundStyle(.secondary) }
            if let s = policy.source, let url = URL(string: s.url) {
                Button { openURL(url) } label: {
                    Label("Fonte: \(s.host ?? s.url) (verificata il \(Formatters.date(s.lastChecked, timeZone: tz)))", systemImage: "link")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                if !s.seenInSearchResults {
                    Label("La fonte non è stata trovata tra i risultati della ricerca", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatusTimeline: View {
    let current: ReturnStatus

    private var steps: [ReturnStatus] {
        let second: ReturnStatus = current == .keep ? .keep : .toReturn
        return [.toEvaluate, second, .requested, .authorized, .packed, .shipped, .awaitingRefund, .refunded, .closed]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, s in
                let done = s.step < current.step
                let isCurrent = s == current
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(isCurrent ? Color.accentColor : (done ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.25)))
                            .frame(width: 14, height: 14)
                        if done { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white) }
                    }
                    Text("\(s.step). \(s.title)")
                        .font(isCurrent ? .subheadline.bold() : .subheadline)
                        .foregroundStyle(isCurrent || done ? .primary : .secondary)
                }
                if index < steps.count - 1 {
                    Rectangle().fill(Color.gray.opacity(0.25)).frame(width: 2, height: 10).padding(.leading, 6)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AttachmentViewer: View {
    let attachment: Attachment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let img = AttachmentStore.loadImage(attachment) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: .infinity)
                    }
                } else {
                    EmptyStateView(title: "Anteprima non disponibile", message: attachment.fileName, symbol: "doc")
                }
            }
            .navigationTitle(attachment.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } }
                if let img = AttachmentStore.loadImage(attachment) {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: Image(uiImage: img), preview: SharePreview(attachment.kind.title, image: Image(uiImage: img)))
                    }
                }
            }
        }
    }
}
