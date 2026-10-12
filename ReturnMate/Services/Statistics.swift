import Foundation

struct StatsSummary: Equatable {
    var totalPurchased: Decimal = 0
    var returnableValue: Decimal = 0
    var refundsExpected: Decimal = 0
    var refundsReceived: Decimal = 0
    var returnCosts: Decimal = 0
    var returnedProductsValue: Decimal = 0
    var completedReturns: Int = 0
    var missedDeadlines: Int = 0
    var purchaseCount: Int = 0

    /// Denaro effettivamente recuperato (rimborsi confermati meno costi di reso).
    var netRecovered: Decimal { refundsReceived - returnCosts }
}

struct GroupStat: Identifiable, Equatable {
    var key: String
    var purchased: Decimal
    var refunded: Decimal
    var count: Int
    var id: String { key }
}

enum Statistics {

    static func isOverdue(_ p: Purchase, now: Date, calendar: Calendar) -> Bool {
        guard let d = p.deadline, p.status.deadlineMatters else { return false }
        return DeadlineEngine.daysRemaining(until: d.date, now: now, calendar: calendar) < 0
    }

    /// Prodotti ancora restituibili: in attesa di decisione/reso e con scadenza non superata.
    static func isReturnable(_ p: Purchase, now: Date, calendar: Calendar) -> Bool {
        guard !p.isArchived, [.toEvaluate, .toReturn].contains(p.status) else { return false }
        guard let d = p.deadline else { return true }
        return DeadlineEngine.daysRemaining(until: d.date, now: now, calendar: calendar) >= 0
    }

    static func summary(_ purchases: [Purchase], now: Date, calendar: Calendar) -> StatsSummary {
        var s = StatsSummary()
        for p in purchases {
            let value = p.totalPrice ?? 0
            s.purchaseCount += 1
            s.totalPurchased += value
            if isReturnable(p, now: now, calendar: calendar) { s.returnableValue += value }
            if p.status.isReturnInProgress {
                s.refundsExpected += p.refund.expectedAmount ?? value
            }
            if p.refund.confirmedByUser, let r = p.refund.receivedAmount {
                s.refundsReceived += r
                s.returnCosts += p.refund.returnCost ?? 0
                s.completedReturns += 1
                s.returnedProductsValue += value
            }
            if isOverdue(p, now: now, calendar: calendar) { s.missedDeadlines += 1 }
        }
        return s
    }

    static func byStore(_ purchases: [Purchase]) -> [GroupStat] {
        group(purchases) { $0.store.trimmingCharacters(in: .whitespaces).isEmpty ? "—" : $0.store }
            .sorted { $0.purchased > $1.purchased }
    }

    static func byMonth(_ purchases: [Purchase], calendar: Calendar) -> [GroupStat] {
        group(purchases) { p in
            guard let d = p.orderDate ?? p.deliveryDate else { return "Senza data" }
            let c = calendar.dateComponents([.year, .month], from: d)
            return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
        }
        .sorted { $0.key < $1.key }
    }

    private static func group(_ purchases: [Purchase], key: (Purchase) -> String) -> [GroupStat] {
        var dict: [String: GroupStat] = [:]
        for p in purchases {
            let k = key(p)
            var g = dict[k] ?? GroupStat(key: k, purchased: 0, refunded: 0, count: 0)
            g.purchased += p.totalPrice ?? 0
            if p.refund.confirmedByUser { g.refunded += p.refund.receivedAmount ?? 0 }
            g.count += 1
            dict[k] = g
        }
        return Array(dict.values)
    }
}
