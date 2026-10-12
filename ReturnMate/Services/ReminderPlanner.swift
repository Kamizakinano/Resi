import Foundation

struct PlannedReminder: Hashable, Identifiable {
    var id: String
    var purchaseID: UUID
    var fireDate: Date
    var title: String
    var body: String
}

/// Pianificazione pura dei promemoria: stessi input → stessi identificativi, quindi nessun duplicato.
enum ReminderPlanner {

    static let prefix = "rm."
    /// iOS conserva al massimo 64 notifiche locali in attesa per app.
    static let maxPending = 60

    static func plan(purchases: [Purchase], settings: AppSettings, now: Date) -> [PlannedReminder] {
        let cal = settings.calendar
        var result: [PlannedReminder] = []
        let offsets = Array(Set(settings.reminderOffsets.filter { $0 >= 0 })).sorted(by: >)

        for p in purchases where !p.isArchived && p.status.deadlineMatters {
            guard let deadline = p.deadline else { continue }
            let deadlineDay = cal.startOfDay(for: deadline.date)
            for offset in offsets {
                guard let day = cal.date(byAdding: .day, value: -offset, to: deadlineDay),
                      let fire = cal.date(bySettingHour: settings.reminderHour, minute: settings.reminderMinute, second: 0, of: day),
                      fire > now else { continue }
                let when: String
                switch offset {
                case 0: when = "Oggi è l'ultimo giorno"
                case 1: when = "Domani scade"
                default: when = "Mancano \(offset) giorni"
                }
                let unverified = deadline.verification == .proposed ? " (scadenza da verificare)" : ""
                result.append(PlannedReminder(
                    id: "\(prefix)\(p.id.uuidString).d\(offset)",
                    purchaseID: p.id,
                    fireDate: fire,
                    title: "Reso \(p.store)",
                    body: "\(when) per restituire \(p.productName)\(unverified)."
                ))
            }

            if settings.verifyReminders && deadline.verification == .proposed {
                // Un solo avviso di verifica: il giorno dopo l'inserimento, oppure 4 giorni prima della scadenza.
                let candidates = [
                    cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: p.createdAt)),
                    cal.date(byAdding: .day, value: -4, to: deadlineDay),
                ].compactMap { $0 }
                    .compactMap { cal.date(bySettingHour: settings.reminderHour, minute: settings.reminderMinute, second: 0, of: $0) }
                    .filter { $0 > now && $0 < deadlineDay }
                if let fire = candidates.min() {
                    result.append(PlannedReminder(
                        id: "\(prefix)\(p.id.uuidString).verify",
                        purchaseID: p.id,
                        fireDate: fire,
                        title: "Verifica la scadenza",
                        body: "La scadenza di reso per \(p.productName) (\(p.store)) non è ancora verificata."
                    ))
                }
            }
        }

        var seen = Set<String>()
        return result
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(maxPending)
            .map { $0 }
    }
}
