import XCTest
@testable import ReturnMate

final class DeadlineEngineTests: XCTestCase {

    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func purchase(order: Date? = nil, delivery: Date? = nil, store: String = "Zalando", country: String = "IT", channel: PurchaseChannel = .online) -> Purchase {
        var p = Purchase(productName: "Scarpe", store: store)
        p.orderDate = order
        p.deliveryDate = delivery
        p.storeCountry = country
        p.channel = channel
        return p
    }

    func storePolicy(_ days: Int, start: StartEvent = .delivery, store: String = "Zalando", official: Bool = true, seen: Bool = true) -> ReturnPolicy {
        ReturnPolicy(store: store, country: "IT", kind: .storePolicy, days: days, startEvent: start,
                     source: PolicySource(url: "https://www.zalando.it/faq/resi", title: "Resi", lastChecked: Date(),
                                          isOfficial: official, seenInSearchResults: seen))
    }

    func testLegalWithdrawalIs14DaysFromDelivery() {
        // Consegna mercoledì 1 ottobre 2025 → 15 ottobre 2025 (mercoledì)
        let p = purchase(order: date(2025, 9, 28), delivery: date(2025, 10, 1))
        let d = DeadlineEngine.proposeDeadline(for: p, storePolicies: [], calendar: cal)
        XCTAssertEqual(d?.kind, .legalWithdrawal)
        XCTAssertTrue(cal.isDate(d!.date, inSameDayAs: date(2025, 10, 15)))
        XCTAssertFalse(d!.extendedForWeekend)
        XCTAssertEqual(d?.verification, .proposed)
    }

    func testLegalDeadlineOnWeekendIsExtendedToMonday() {
        // Consegna sabato 4 ottobre 2025 → 18 ottobre (sabato) → lunedì 20 ottobre
        let p = purchase(delivery: date(2025, 10, 4))
        let d = DeadlineEngine.proposeDeadline(for: p, storePolicies: [], calendar: cal)!
        XCTAssertTrue(cal.isDate(d.date, inSameDayAs: date(2025, 10, 20)))
        XCTAssertTrue(d.extendedForWeekend)
    }

    func testStorePolicyNotExtendedOnWeekend() {
        let p = purchase(delivery: date(2025, 10, 4))
        let policy = ReturnPolicy(store: "Zalando", country: "IT", kind: .storePolicy, days: 14, startEvent: .delivery)
        let d = DeadlineEngine.deadline(for: p, policy: policy, calendar: cal)!
        XCTAssertTrue(cal.isDate(d.date, inSameDayAs: date(2025, 10, 18)))
    }

    func testLongerStorePolicyWins() {
        let p = purchase(delivery: date(2025, 10, 1))
        let d = DeadlineEngine.proposeDeadline(for: p, storePolicies: [storePolicy(30)], calendar: cal)!
        XCTAssertEqual(d.kind, .storePolicy)
        XCTAssertTrue(cal.isDate(d.date, inSameDayAs: date(2025, 10, 31)))
    }

    func testShorterStorePolicyLosesToLegalRight() {
        let p = purchase(delivery: date(2025, 10, 1))
        let d = DeadlineEngine.proposeDeadline(for: p, storePolicies: [storePolicy(7)], calendar: cal)!
        XCTAssertEqual(d.kind, .legalWithdrawal)
    }

    func testInStorePurchaseHasNoLegalWithdrawal() {
        let p = purchase(delivery: date(2025, 10, 1), channel: .inStore)
        XCTAssertNil(DeadlineEngine.proposeDeadline(for: p, storePolicies: [], calendar: cal))
    }

    func testNonEUCountryHasNoLegalRule() {
        let p = purchase(delivery: date(2025, 10, 1), country: "US")
        XCTAssertNil(DeadlineEngine.proposeDeadline(for: p, storePolicies: [], calendar: cal))
    }

    func testMissingDeliveryUsesOrderDateWithWarning() {
        let p = purchase(order: date(2025, 10, 1))
        let d = DeadlineEngine.proposeDeadline(for: p, storePolicies: [], calendar: cal)!
        XCTAssertFalse(d.warnings.filter { $0.contains("consegna mancante") }.isEmpty)
        // Non verificabile: la regola decorre dalla consegna, che manca.
        XCTAssertTrue(DeadlineEngine.verificationIssues(for: d, purchase: p, calendar: cal).contains(.missingStartDate))
    }

    func testNoDatesNoDeadline() {
        XCTAssertNil(DeadlineEngine.proposeDeadline(for: purchase(), storePolicies: [], calendar: cal))
    }

    func testVerifiableWithOfficialSourceAndMatchingCalculation() {
        let p = purchase(delivery: date(2025, 10, 1))
        let d = DeadlineEngine.proposeDeadline(for: p, storePolicies: [storePolicy(30)], calendar: cal)!
        XCTAssertEqual(DeadlineEngine.verificationIssues(for: d, purchase: p, calendar: cal), [])
        XCTAssertTrue(DeadlineEngine.canVerify(d, purchase: p, calendar: cal))
    }

    func testCannotVerifyWithoutSource() {
        let p = purchase(delivery: date(2025, 10, 1))
        var d = DeadlineEngine.proposeDeadline(for: p, storePolicies: [storePolicy(30)], calendar: cal)!
        d.source = nil
        XCTAssertTrue(DeadlineEngine.verificationIssues(for: d, purchase: p, calendar: cal).contains(.missingSource))
    }

    func testCannotVerifyUnofficialOrUnseenSource() {
        let p = purchase(delivery: date(2025, 10, 1))
        let d1 = DeadlineEngine.deadline(for: p, policy: storePolicy(30, official: false), calendar: cal)!
        XCTAssertTrue(DeadlineEngine.verificationIssues(for: d1, purchase: p, calendar: cal).contains(.sourceNotOfficial))
        let d2 = DeadlineEngine.deadline(for: p, policy: storePolicy(30, seen: false), calendar: cal)!
        XCTAssertTrue(DeadlineEngine.verificationIssues(for: d2, purchase: p, calendar: cal).contains(.sourceNotFound))
    }

    func testCannotVerifyPolicyOfAnotherStore() {
        let p = purchase(delivery: date(2025, 10, 1), store: "Amazon")
        let d = DeadlineEngine.deadline(for: p, policy: storePolicy(30, store: "Zalando"), calendar: cal)!
        XCTAssertTrue(DeadlineEngine.verificationIssues(for: d, purchase: p, calendar: cal).contains(.notRelevant))
    }

    func testStoreNameNormalization() {
        XCTAssertEqual(DeadlineEngine.normalizeStore("Zalando.it"), DeadlineEngine.normalizeStore("zalando"))
        XCTAssertEqual(DeadlineEngine.normalizeStore("www.Amazon.it"), DeadlineEngine.normalizeStore("Amazon"))
        XCTAssertEqual(DeadlineEngine.normalizeStore("H&M"), "hm")
    }

    func testManualDateEditBreaksCalculationCheck() {
        let p = purchase(delivery: date(2025, 10, 1))
        var d = DeadlineEngine.proposeDeadline(for: p, storePolicies: [storePolicy(30)], calendar: cal)!
        d.date = date(2025, 11, 15)
        XCTAssertTrue(DeadlineEngine.verificationIssues(for: d, purchase: p, calendar: cal).contains(.calculationMismatch))
    }

    func testChangedDeliveryDateInvalidatesVerification() {
        var p = purchase(delivery: date(2025, 10, 1))
        let d = DeadlineEngine.proposeDeadline(for: p, storePolicies: [storePolicy(30)], calendar: cal)!
        p.deliveryDate = date(2025, 10, 3)
        XCTAssertTrue(DeadlineEngine.verificationIssues(for: d, purchase: p, calendar: cal).contains(.startDateMismatch))
    }

    func testDaysRemaining() {
        let now = date(2025, 10, 10)
        XCTAssertEqual(DeadlineEngine.daysRemaining(until: date(2025, 10, 10), now: now, calendar: cal), 0)
        XCTAssertEqual(DeadlineEngine.daysRemaining(until: date(2025, 10, 13), now: now, calendar: cal), 3)
        XCTAssertEqual(DeadlineEngine.daysRemaining(until: date(2025, 10, 8), now: now, calendar: cal), -2)
    }
}
