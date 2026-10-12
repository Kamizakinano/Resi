import XCTest
@testable import ReturnMate

final class ReturnFlowTests: XCTestCase {

    func testForwardSkipLogsSkippedStates() throws {
        var p = Purchase(productName: "Cuffie", store: "Amazon")
        try ReturnFlow.apply(.toReturn, to: &p)
        try ReturnFlow.apply(.shipped, to: &p)
        XCTAssertEqual(p.status, .shipped)
        XCTAssertNotNil(p.returnInfo.shippedDate)
        let last = p.history.last!.message
        XCTAssertTrue(last.contains("saltati"))
        XCTAssertTrue(last.contains(ReturnStatus.requested.title))
    }

    func testCannotGoBackwards() {
        var p = Purchase(productName: "Cuffie", store: "Amazon")
        p.status = .shipped
        XCTAssertThrowsError(try ReturnFlow.apply(.requested, to: &p))
        XCTAssertFalse(ReturnFlow.canTransition(from: .shipped, to: .keep))
    }

    func testRefundedRequiresUserConfirmation() throws {
        var p = Purchase(productName: "Cuffie", store: "Amazon")
        p.status = .awaitingRefund
        XCTAssertThrowsError(try ReturnFlow.apply(.refunded, to: &p)) { error in
            XCTAssertEqual(error as? ReturnFlow.TransitionError, .refundNotConfirmed)
        }
        ReturnFlow.confirmRefund(&p, amount: 10, date: Date(), returnCost: 2)
        try ReturnFlow.apply(.refunded, to: &p)
        XCTAssertEqual(p.status, .refunded)
        XCTAssertEqual(p.refund.netRecovered, 8)
    }

    func testKeepCanBecomeReturnAgain() {
        XCTAssertTrue(ReturnFlow.canTransition(from: .keep, to: .toReturn))
        XCTAssertTrue(ReturnFlow.canTransition(from: .keep, to: .closed))
        XCTAssertFalse(ReturnFlow.canTransition(from: .keep, to: .shipped))
        XCTAssertTrue(ReturnFlow.allowedTargets(from: .closed).isEmpty)
    }

    func testUndoLastStatus() throws {
        var p = Purchase(productName: "Cuffie", store: "Amazon")
        try ReturnFlow.apply(.toReturn, to: &p)
        try ReturnFlow.apply(.requested, to: &p)
        XCTAssertTrue(ReturnFlow.undoLast(&p))
        XCTAssertEqual(p.status, .toReturn)
        // Un secondo annullamento non ha effetto (l'ultima voce è l'annullamento).
        XCTAssertFalse(ReturnFlow.undoLast(&p))
    }
}

final class ReminderPlannerTests: XCTestCase {

    func makeSettings() -> AppSettings {
        var s = AppSettings()
        s.timeZoneID = "Europe/Rome"
        s.reminderOffsets = [7, 3, 1, 0]
        s.reminderHour = 9
        return s
    }

    func purchase(deadlineIn days: Int, now: Date, verified: Bool = true, status: ReturnStatus = .toEvaluate) -> Purchase {
        let cal = makeSettings().calendar
        var p = Purchase(productName: "Lampada", store: "IKEA")
        p.status = status
        p.createdAt = cal.date(byAdding: .day, value: -5, to: now)!
        p.deadline = Deadline(date: cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: now))!,
                              kind: .storePolicy, startEvent: .delivery, startDate: nil, days: 30,
                              verification: verified ? .verified : .proposed, source: nil, rule: "30 giorni")
        return p
    }

    func testPlansOnlyFutureOffsets() {
        let s = makeSettings()
        let now = s.calendar.date(from: DateComponents(year: 2025, month: 10, day: 10, hour: 12))!
        let p = purchase(deadlineIn: 5, now: now)
        let plan = ReminderPlanner.plan(purchases: [p], settings: s, now: now)
        // 7 giorni prima è già passato; restano 3, 1, 0.
        XCTAssertEqual(plan.map(\.id), ["rm.\(p.id.uuidString).d3", "rm.\(p.id.uuidString).d1", "rm.\(p.id.uuidString).d0"])
        XCTAssertEqual(s.calendar.component(.hour, from: plan[0].fireDate), 9)
    }

    func testNoDuplicatesAndStableIDs() {
        let s = makeSettings()
        let now = Date()
        let p = purchase(deadlineIn: 20, now: now)
        let a = ReminderPlanner.plan(purchases: [p, p], settings: s, now: now)
        let b = ReminderPlanner.plan(purchases: [p], settings: s, now: now)
        XCTAssertEqual(Set(a.map(\.id)).count, a.count)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
    }

    func testNoRemindersWhenKeptClosedOrArchived() {
        let s = makeSettings()
        let now = Date()
        var archived = purchase(deadlineIn: 20, now: now)
        archived.isArchived = true
        let kept = purchase(deadlineIn: 20, now: now, status: .keep)
        let closed = purchase(deadlineIn: 20, now: now, status: .closed)
        let shipped = purchase(deadlineIn: 20, now: now, status: .shipped)
        XCTAssertTrue(ReminderPlanner.plan(purchases: [archived, kept, closed, shipped], settings: s, now: now).isEmpty)
    }

    func testVerifyReminderForProposedDeadline() {
        let s = makeSettings()
        let now = s.calendar.date(from: DateComponents(year: 2025, month: 10, day: 10, hour: 12))!
        let p = purchase(deadlineIn: 20, now: now, verified: false)
        let plan = ReminderPlanner.plan(purchases: [p], settings: s, now: now)
        XCTAssertEqual(plan.filter { $0.id.hasSuffix(".verify") }.count, 1)
        var s2 = s
        s2.verifyReminders = false
        XCTAssertTrue(ReminderPlanner.plan(purchases: [p], settings: s2, now: now).filter { $0.id.hasSuffix(".verify") }.isEmpty)
    }

    func testCapsPendingCount() {
        let s = makeSettings()
        let now = Date()
        let many = (0..<40).map { _ in purchase(deadlineIn: 30, now: now) }
        XCTAssertLessThanOrEqual(ReminderPlanner.plan(purchases: many, settings: s, now: now).count, ReminderPlanner.maxPending)
    }
}
