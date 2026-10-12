import XCTest
@testable import ReturnMate

final class ParsingTests: XCTestCase {

    let tz = TimeZone(identifier: "Europe/Rome")!

    func comps(_ d: Date?) -> DateComponents? {
        guard let d else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.dateComponents([.year, .month, .day], from: d)
    }

    func testDecimalParsing() {
        XCTAssertEqual(Formatters.parseDecimal("12,99"), Decimal(string: "12.99"))
        XCTAssertEqual(Formatters.parseDecimal("1.234,56"), Decimal(string: "1234.56"))
        XCTAssertEqual(Formatters.parseDecimal("1,234.56"), Decimal(string: "1234.56"))
        XCTAssertEqual(Formatters.parseDecimal("€ 89.95"), Decimal(string: "89.95"))
        XCTAssertEqual(Formatters.parseDecimal("1.234"), Decimal(string: "1234"))
        XCTAssertNil(Formatters.parseDecimal("abc"))
    }

    func testItalianOrderEmail() {
        let text = """
        Grazie per il tuo ordine su Zalando!
        Numero d'ordine: 10203040506070
        Data ordine: 03/10/2025
        Consegnato il 7 ottobre 2025
        Totale: 129,90 €
        Domande? servizio@zalando.it
        """
        let d = HeuristicParser.parse(text, source: .emailText, timeZone: tz)
        XCTAssertEqual(d.store, "Zalando")
        XCTAssertEqual(d.storeCountry, "IT")
        XCTAssertEqual(d.orderNumber, "10203040506070")
        XCTAssertEqual(comps(d.orderDate), DateComponents(year: 2025, month: 10, day: 3))
        XCTAssertEqual(comps(d.deliveryDate), DateComponents(year: 2025, month: 10, day: 7))
        XCTAssertEqual(d.items.first?.price, Decimal(string: "129.90"))
        XCTAssertEqual(d.currency, "EUR")
        // Non inventa il nome del prodotto.
        XCTAssertEqual(d.items.first?.name, "")
        XCTAssertTrue(d.warnings.contains { $0.contains("Nome del prodotto") })
        // 03/10 è ambigua (giorno/mese o mese/giorno).
        XCTAssertTrue(d.warnings.contains { $0.contains("ambigua") })
    }

    func testAmazonOrderNumber() {
        let d = HeuristicParser.parse("Ordine n. 405-1234567-7654321 Amazon.it", source: .screenshot, timeZone: tz)
        XCTAssertEqual(d.orderNumber, "405-1234567-7654321")
        XCTAssertEqual(d.store, "Amazon")
    }

    func testUnambiguousDate() {
        let d = HeuristicParser.parse("Data ordine 25/09/2025", source: .emailText, timeZone: tz)
        XCTAssertEqual(comps(d.orderDate), DateComponents(year: 2025, month: 9, day: 25))
        XCTAssertFalse(d.warnings.contains { $0.contains("ambigua") })
    }

    func testNothingFoundProducesWarningsNotData() {
        let d = HeuristicParser.parse("ciao", source: .emailText, timeZone: tz)
        XCTAssertNil(d.orderDate)
        XCTAssertNil(d.items.first?.price)
        XCTAssertTrue(d.warnings.contains("Prezzo non trovato."))
    }

    func testAIDraftMapping() {
        let obj: [String: Any] = [
            "store": "IKEA", "store_country": "it", "channel": "unknown", "order_number": NSNull(),
            "order_date": "2025-10-02", "delivery_date": NSNull(), "currency": "eur", "order_url": NSNull(),
            "items": [["name": "Lampada", "unit_price": 39.99, "quantity": 2, "product_url": NSNull()],
                      ["name": "Sedia", "unit_price": NSNull(), "quantity": 1, "product_url": NSNull()]],
            "warnings": ["Prezzo della sedia illeggibile"],
        ]
        let d = ClaudeClient.draft(from: obj)
        XCTAssertEqual(d.store, "IKEA")
        XCTAssertEqual(d.storeCountry, "IT")
        XCTAssertEqual(d.currency, "EUR")
        XCTAssertEqual(d.items.count, 2)
        XCTAssertEqual(d.items[0].price, Decimal(string: "39.99"))
        XCTAssertEqual(d.items[0].quantity, 2)
        XCTAssertNil(d.items[1].price)
        XCTAssertNil(d.deliveryDate)
        XCTAssertTrue(d.warnings.contains("Prezzo della sedia illeggibile"))
        let purchases = d.makePurchases(receipt: nil, productPhoto: nil)
        XCTAssertEqual(purchases.count, 2)
        XCTAssertEqual(purchases[0].orderGroup, purchases[1].orderGroup)
    }

    func testResearchRejectsUnseenSource() {
        let obj: [String: Any] = [
            "store_policy": ["days": 30, "start_event": "delivery", "conditions": [], "exclusions": [], "return_methods": [],
                             "free_return": true, "source_url": "https://www.ikea.com/it/it/customer-service/returns/",
                             "source_title": "Resi IKEA", "source_is_official_store_site": true, "notes": ""],
            "warranty_notes": NSNull(), "insufficient_information": false, "message": "Trovata",
        ]
        let seen = ClaudeClient.researchResult(from: obj, store: "IKEA", country: "IT",
                                               seenURLs: ["https://ikea.com/it/it/customer-service/returns"], now: Date())
        XCTAssertEqual(seen.policies.first?.source?.seenInSearchResults, true)
        XCTAssertEqual(seen.policies.first?.days, 30)
        XCTAssertFalse(seen.insufficient)
        let unseen = ClaudeClient.researchResult(from: obj, store: "IKEA", country: "IT", seenURLs: [], now: Date())
        XCTAssertEqual(unseen.policies.first?.source?.seenInSearchResults, false)
    }

    func testLinkPageParsing() {
        let html = """
        <html><head><title>Fallback</title>
        <meta property="og:title" content="Lampada &amp; paralume">
        <meta property="product:price:amount" content="39.99">
        <meta property="product:price:currency" content="EUR">
        <script>var x = 1;</script></head><body><p>Descrizione</p></body></html>
        """
        let page = LinkFetcher.parse(html: html, url: URL(string: "https://www.ikea.com/it/it/p/lampada")!)
        XCTAssertEqual(page.title, "Lampada & paralume")
        XCTAssertEqual(page.price, Decimal(string: "39.99"))
        XCTAssertEqual(page.currency, "EUR")
        XCTAssertFalse(page.text.contains("var x"))
    }
}

final class ValidationAndStatsTests: XCTestCase {

    func testRequiredFields() {
        let p = Purchase(productName: " ", store: "")
        let errors = PurchaseValidator.validate(p).filter { $0.severity == .error }.map(\.field)
        XCTAssertTrue(errors.contains("productName"))
        XCTAssertTrue(errors.contains("store"))
    }

    func testDeliveryBeforeOrderIsError() {
        var p = Purchase(productName: "A", store: "B")
        p.orderDate = Date()
        p.deliveryDate = Date().addingTimeInterval(-5 * 86_400)
        XCTAssertTrue(PurchaseValidator.validate(p).contains { $0.field == "deliveryDate" && $0.severity == .error })
    }

    func testInvalidURL() {
        var p = Purchase(productName: "A", store: "B")
        p.productURL = "not a url"
        XCTAssertTrue(PurchaseValidator.hasErrors(p))
        p.productURL = "https://www.example.com/x"
        XCTAssertFalse(PurchaseValidator.hasErrors(p))
    }

    func testStatsDistinguishRecoveredFromReturnedValue() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome")!
        let now = Date()
        var a = Purchase(productName: "A", store: "S")
        a.price = 100
        ReturnFlow.confirmRefund(&a, amount: 90, date: now, returnCost: 5)
        a.status = .refunded
        var b = Purchase(productName: "B", store: "S")
        b.price = 50
        b.status = .shipped
        var c = Purchase(productName: "C", store: "T")
        c.price = 20
        c.deadline = Deadline(date: cal.date(byAdding: .day, value: -2, to: now)!, kind: .legalWithdrawal,
                              startEvent: .delivery, startDate: nil, days: 14, rule: "14 giorni")
        let s = Statistics.summary([a, b, c], now: now, calendar: cal)
        XCTAssertEqual(s.totalPurchased, 170)
        XCTAssertEqual(s.refundsReceived, 90)
        XCTAssertEqual(s.netRecovered, 85)
        XCTAssertEqual(s.returnedProductsValue, 100)
        XCTAssertEqual(s.refundsExpected, 50)
        XCTAssertEqual(s.missedDeadlines, 1)
        XCTAssertEqual(s.returnableValue, 0)
        XCTAssertEqual(Statistics.byStore([a, b, c]).first?.key, "S")
    }

    func testCSVEscaping() {
        var p = Purchase(productName: "Divano; 3 posti \"Comfort\"", store: "IKEA")
        p.price = Decimal(string: "499.5")
        let csv = Exporter.csv([p], timeZone: .current)
        XCTAssertTrue(csv.contains("\"Divano; 3 posti \"\"Comfort\"\"\""))
    }

    @MainActor
    func testStoreAddComputesDeadlineAndValidates() {
        let store = DataStore(inMemory: true)
        var p = Purchase(productName: "Lampada", store: "IKEA")
        p.deliveryDate = Date()
        XCTAssertTrue(store.add([p]).isEmpty)
        XCTAssertEqual(store.purchases.first?.deadline?.kind, .legalWithdrawal)
        XCTAssertEqual(store.purchases.first?.deadline?.verification, .proposed)
        // La fonte del recesso legale è ufficiale e il calcolo torna: la scadenza è verificabile.
        let id = store.purchases[0].id
        XCTAssertTrue(store.verifyDeadline(id).isEmpty)
        XCTAssertEqual(store.purchase(id)?.deadline?.verification, .verified)

        let invalid = Purchase(productName: "", store: "")
        XCTAssertFalse(store.add([invalid]).isEmpty)
        XCTAssertEqual(store.purchases.count, 1)
    }

    @MainActor
    func testManualDeadlineIsLoggedAndProposed() {
        let store = DataStore(inMemory: true)
        var p = Purchase(productName: "Lampada", store: "IKEA")
        p.deliveryDate = Date()
        store.add([p])
        let id = store.purchases[0].id
        store.setManualDeadline(id, date: Date().addingTimeInterval(40 * 86_400), days: nil, startEvent: .delivery,
                                kind: .manual, rule: "Accordo con il negozio", sourceURL: "", sourceIsOfficial: false)
        let updated = store.purchase(id)!
        XCTAssertEqual(updated.deadline?.verification, .proposed)
        XCTAssertTrue(updated.deadline!.manuallyEdited)
        XCTAssertTrue(updated.history.contains { $0.message.contains("manualmente") })
        // Senza fonte e senza regola in giorni non è verificabile.
        XCTAssertFalse(store.verifyDeadline(id).isEmpty)
    }
}
