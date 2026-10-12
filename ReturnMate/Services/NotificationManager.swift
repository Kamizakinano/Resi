import Foundation
import UserNotifications
import Observation

@MainActor
@Observable
final class NotificationManager {
    static let shared = NotificationManager()

    var status: UNAuthorizationStatus = .notDetermined
    var pendingCount: Int = 0

    var isEnabled: Bool { status == .authorized || status == .provisional || status == .ephemeral }

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = settings.authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshStatus()
        return granted
    }

    /// Sostituisce tutti i promemoria dell'app con quelli pianificati. Gli identificativi sono
    /// deterministici: una nuova pianificazione aggiorna quelle esistenti senza duplicarle.
    func sync(_ planned: [PlannedReminder], timeZone: TimeZone) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(ReminderPlanner.prefix) }
        let keep = Set(planned.map(\.id))
        center.removePendingNotificationRequests(withIdentifiers: ours.filter { !keep.contains($0) })

        await refreshStatus()
        guard isEnabled else {
            pendingCount = 0
            return
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        for r in planned {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            content.sound = .default
            content.userInfo = ["purchaseID": r.purchaseID.uuidString]
            var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: r.fireDate)
            comps.timeZone = timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            // Stesso identificativo = la richiesta esistente viene sostituita.
            try? await center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: trigger))
        }
        pendingCount = planned.count
    }
}
