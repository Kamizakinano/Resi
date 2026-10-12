import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class DataStore {
    var data: AppData
    var lastError: String?
    var researchInProgress: Set<UUID> = []

    var purchases: [Purchase] { data.purchases }
    var settings: AppSettings { data.settings }
    var calendar: Calendar { data.settings.calendar }

    private let persist: Bool

    init(inMemory: Bool = false, initial: AppData? = nil) {
        persist = !inMemory
        if let initial {
            data = initial
        } else if !inMemory, let loaded = Persistence.load() {
            data = loaded
        } else {
            data = AppData()
        }
    }

    // MARK: - Salvataggio

    func save() {
        guard persist else { return }
        do {
            try Persistence.save(data)
        } catch {
            lastError = "Salvataggio non riuscito: \(error.localizedDescription)"
        }
    }

    func rescheduleReminders() {
        let planned = ReminderPlanner.plan(purchases: data.purchases, settings: data.settings, now: Date())
        let tz = data.settings.timeZone
        guard persist else { return }
        Task { await NotificationManager.shared.sync(planned, timeZone: tz) }
    }

    private func commit() {
        save()
        rescheduleReminders()
    }

    // MARK: - Profilo e impostazioni

    func createProfile(name: String, email: String) {
        data.profile = UserProfile(name: name.trimmingCharacters(in: .whitespaces),
                                   email: email.trimmingCharacters(in: .whitespaces))
        save()
    }

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        let before = data.settings
        change(&data.settings)
        if before.timeZoneID != data.settings.timeZoneID {
            // Cambia il fuso orario: ricalcola le scadenze non modificate manualmente.
            for i in data.purchases.indices { recomputeDeadline(at: i, reason: "Fuso orario aggiornato") }
        }
        commit()
    }

    /// Elimina account e tutti i dati locali (acquisti, allegati, chiavi).
    func deleteAccount() {
        Persistence.wipe()
        Keychain.deleteAll()
        data = AppData()
        commit()
    }

    // MARK: - Acquisti

    func purchase(_ id: UUID) -> Purchase? {
        data.purchases.first { $0.id == id }
    }

    func items(inOrder group: UUID) -> [Purchase] {
        data.purchases.filter { $0.orderGroup == group }
    }

    /// Aggiunge gli acquisti dopo la validazione. Restituisce gli errori bloccanti, se presenti.
    @discardableResult
    func add(_ newItems: [Purchase]) -> [ValidationIssue] {
        let errors = newItems.flatMap { PurchaseValidator.validate($0) }.filter { $0.severity == .error }
        guard errors.isEmpty else { return errors }
        for var p in newItems {
            p.createdAt = Date()
            p.log(.created, "Acquisto aggiunto (\(p.source.title))")
            let cached = data.policyCache[policyKey(store: p.store, country: p.storeCountry)] ?? []
            p.policies = cached
            applyProposedDeadline(&p, reason: nil)
            data.purchases.append(p)
        }
        commit()
        return []
    }

    @discardableResult
    func update(_ updated: Purchase, message: String = "Dati modificati") -> [ValidationIssue] {
        let errors = PurchaseValidator.validate(updated).filter { $0.severity == .error }
        guard errors.isEmpty else { return errors }
        guard let i = data.purchases.firstIndex(where: { $0.id == updated.id }) else { return [] }
        let old = data.purchases[i]
        var p = updated
        let datesChanged = old.orderDate != p.orderDate || old.deliveryDate != p.deliveryDate
            || old.storeCountry != p.storeCountry || old.channel != p.channel
        let storeChanged = DeadlineEngine.normalizeStore(old.store) != DeadlineEngine.normalizeStore(p.store)
        if storeChanged {
            p.policies = data.policyCache[policyKey(store: p.store, country: p.storeCountry)] ?? []
        }
        p.log(.edited, message)
        data.purchases[i] = p
        if datesChanged || storeChanged {
            recomputeDeadline(at: i, reason: "Dati dell'acquisto modificati")
        }
        commit()
        return []
    }

    func mutate(_ id: UUID, _ change: (inout Purchase) throws -> Void) rethrows {
        guard let i = data.purchases.firstIndex(where: { $0.id == id }) else { return }
        // Si lavora su una copia: le closure possono leggere lo store (es. calendario e impostazioni)
        // senza violare l'accesso esclusivo a `data`.
        var p = data.purchases[i]
        try change(&p)
        p.updatedAt = Date()
        data.purchases[i] = p
        commit()
    }

    func delete(_ id: UUID) {
        guard let p = purchase(id) else { return }
        p.attachments.forEach(AttachmentStore.delete)
        data.purchases.removeAll { $0.id == id }
        commit()
    }

    func setArchived(_ id: UUID, _ archived: Bool) {
        mutate(id) { p in
            p.isArchived = archived
            p.log(.archive, archived ? "Archiviato" : "Ripristinato dall'archivio")
        }
    }

    func changeStatus(_ id: UUID, to status: ReturnStatus) throws {
        try mutate(id) { p in try ReturnFlow.apply(status, to: &p) }
    }

    func addAttachment(_ id: UUID, image: UIImage, kind: AttachmentKind) {
        do {
            let att = try AttachmentStore.saveImage(image, kind: kind)
            mutate(id) { p in
                p.attachments.append(att)
                if kind == .productPhoto && p.imageAttachmentID == nil { p.imageAttachmentID = att.id }
                p.log(.attachment, "Allegato aggiunto: \(kind.title)")
            }
        } catch {
            lastError = "Impossibile salvare l'allegato."
        }
    }

    func removeAttachment(_ id: UUID, attachment: Attachment) {
        AttachmentStore.delete(attachment)
        mutate(id) { p in
            p.attachments.removeAll { $0.id == attachment.id }
            if p.imageAttachmentID == attachment.id { p.imageAttachmentID = p.attachments.first(where: \.isImage)?.id }
            p.log(.attachment, "Allegato rimosso: \(attachment.kind.title)")
        }
    }

    // MARK: - Scadenze

    func policyKey(store: String, country: String) -> String {
        "\(DeadlineEngine.normalizeStore(store))|\(country.uppercased())"
    }

    private func applyProposedDeadline(_ p: inout Purchase, reason: String?) {
        if let d = DeadlineEngine.proposeDeadline(for: p, storePolicies: p.policies, calendar: calendar) {
            let changed = p.deadline?.date != d.date
            p.deadline = d
            if changed || reason == nil {
                p.log(.deadline, "Scadenza proposta: \(Formatters.date(d.date, timeZone: settings.timeZone)) — \(d.rule)")
            }
        } else {
            if p.deadline != nil { p.log(.deadline, "Scadenza rimossa: \(reason ?? "dati insufficienti")") }
            p.deadline = nil
        }
        // Senza una scadenza calcolabile chiediamo all'utente di inserirla o confermarla.
        p.needsManualDeadline = p.deadline == nil
    }

    private func recomputeDeadline(at i: Int, reason: String) {
        var p = data.purchases[i]
        if p.deadline?.manuallyEdited == true { return }
        applyProposedDeadline(&p, reason: reason)
        data.purchases[i] = p
    }

    /// Imposta la scadenza manualmente; resta "proposta" finché non supera la verifica.
    func setManualDeadline(_ id: UUID, date: Date, days: Int?, startEvent: StartEvent,
                           kind: PolicyKind, rule: String, sourceURL: String, sourceIsOfficial: Bool) {
        mutate(id) { p in
            let start: Date? = startEvent == .delivery ? p.deliveryDate : p.orderDate
            var source: PolicySource?
            let trimmed = sourceURL.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                source = PolicySource(url: PurchaseValidator.normalizedURL(trimmed), title: "Fonte inserita dall'utente",
                                      lastChecked: Date(), isOfficial: sourceIsOfficial, seenInSearchResults: true)
            }
            let old = p.deadline?.date
            p.deadline = Deadline(
                date: calendar.startOfDay(for: date), kind: kind, startEvent: startEvent, startDate: start,
                days: days, verification: .proposed, source: source,
                rule: rule.isEmpty ? (days.map { "\($0) giorni \(startEvent.title)" } ?? "") : rule,
                extendedForWeekend: false, manuallyEdited: true, warnings: [],
                policyStore: kind == .legalWithdrawal ? "*" : p.store, policyCountry: p.storeCountry
            )
            p.needsManualDeadline = false
            p.log(.deadline, "Scadenza modificata manualmente: \(Formatters.date(old, timeZone: settings.timeZone)) → \(Formatters.date(date, timeZone: settings.timeZone))")
        }
    }

    /// Ritorna alla scadenza calcolata automaticamente.
    func resetDeadline(_ id: UUID) {
        mutate(id) { p in
            p.deadline?.manuallyEdited = false
            applyProposedDeadline(&p, reason: "Ripristino del calcolo automatico")
            p.log(.deadline, "Ripristinato il calcolo automatico della scadenza")
        }
    }

    /// Prova a contrassegnare la scadenza come verificata. Restituisce i motivi del rifiuto.
    func verifyDeadline(_ id: UUID) -> [DeadlineEngine.VerificationIssue] {
        guard let p = purchase(id), let d = p.deadline else { return [.missingSource] }
        let issues = DeadlineEngine.verificationIssues(for: d, purchase: p, calendar: calendar)
        guard issues.isEmpty else { return issues }
        mutate(id) { p in
            p.deadline?.verification = .verified
            p.log(.verification, "Scadenza verificata (fonte: \(d.source?.host ?? "—"), regola: \(d.rule))")
        }
        return []
    }

    func unverifyDeadline(_ id: UUID) {
        mutate(id) { p in
            p.deadline?.verification = .proposed
            p.log(.verification, "Verifica rimossa")
        }
    }

    /// Salva le politiche trovate e ricalcola la scadenza di tutti gli acquisti dello stesso negozio.
    func applyResearch(_ policies: [ReturnPolicy], store: String, country: String) {
        let key = policyKey(store: store, country: country)
        let storePolicies = policies.filter { $0.kind == .storePolicy }
        data.policyCache[key] = storePolicies
        for i in data.purchases.indices where policyKey(store: data.purchases[i].store, country: data.purchases[i].storeCountry) == key {
            data.purchases[i].policies = storePolicies
            let found = storePolicies.first
            data.purchases[i].log(.policy, found != nil
                ? "Politica di reso trovata: \(found!.days.map { "\($0) giorni" } ?? "durata non indicata") (\(found!.source?.host ?? "fonte non indicata"))"
                : "Nessuna politica del negozio trovata")
            if data.purchases[i].deadline?.verification != .verified {
                recomputeDeadline(at: i, reason: "Politica aggiornata")
            }
        }
        commit()
    }

    // MARK: - AI

    var aiScanLimit: Int { PremiumManager.shared.isPremium ? 200 : 10 }

    var aiScansRemaining: Int {
        let month = Formatters.isoDay(Date()).prefix(7)
        let used = data.settings.aiScansMonth == month ? data.settings.aiScansThisMonth : 0
        return max(0, aiScanLimit - used)
    }

    func registerAIScan() {
        let month = String(Formatters.isoDay(Date()).prefix(7))
        if data.settings.aiScansMonth != month {
            data.settings.aiScansMonth = month
            data.settings.aiScansThisMonth = 0
        }
        data.settings.aiScansThisMonth += 1
        save()
    }

    // MARK: - Viste derivate

    func daysRemaining(_ p: Purchase, now: Date = Date()) -> Int? {
        guard let d = p.deadline else { return nil }
        return DeadlineEngine.daysRemaining(until: d.date, now: now, calendar: calendar)
    }

    /// Acquisti che richiedono attenzione, ordinati per urgenza.
    func attentionItems(now: Date = Date()) -> [Purchase] {
        data.purchases
            .filter { !$0.isArchived }
            .filter { p in
                if p.status.deadlineMatters {
                    if p.deadline == nil || p.needsManualDeadline { return true }
                    if p.deadline?.verification == .proposed { return true }
                    if let days = daysRemaining(p, now: now), days <= 14 { return true }
                }
                return p.status == .awaitingRefund || p.status == .shipped
            }
            .sorted { urgency($0, now: now) < urgency($1, now: now) }
    }

    func urgency(_ p: Purchase, now: Date = Date()) -> Int {
        guard p.status.deadlineMatters else { return 10_000 }
        guard let days = daysRemaining(p, now: now) else { return 5_000 }
        return days < 0 ? 1_000 - days : days
    }
}
