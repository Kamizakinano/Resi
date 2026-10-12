import Foundation

/// Dati dimostrativi usati solo con l'argomento di avvio "-demoData YES" (screenshot automatici).
enum DemoData {
    static var featuredID: UUID?

    static var sampleDraft: ExtractionDraft {
        var d = ExtractionDraft()
        let cal = Calendar.current
        d.store = "Zalando"
        d.storeCountry = "IT"
        d.orderNumber = "10203040506070"
        d.orderDate = cal.date(byAdding: .day, value: -5, to: Date())
        d.deliveryDate = cal.date(byAdding: .day, value: -2, to: Date())
        d.items = [
            ExtractedItem(name: "Sneakers in pelle bianche", price: Decimal(string: "89.95"), quantity: 1),
            ExtractedItem(name: "Giacca impermeabile", price: Decimal(string: "129.00"), quantity: 1),
        ]
        d.warnings = ["Data di consegna letta dall'email di spedizione: controllala."]
        d.source = .screenshot
        d.usedAI = true
        return d
    }

    static func make(now: Date = Date()) -> AppData {
        var data = AppData()
        data.profile = UserProfile(name: "Giulia Rossi", email: "giulia@example.com")
        let cal = data.settings.calendar
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))! }

        let storeSource = PolicySource(url: "https://www.example.com/resi", title: "Pagina resi (dato dimostrativo)",
                                       lastChecked: day(-1), isOfficial: true, seenInSearchResults: true)
        func storePolicy(_ store: String, _ days: Int) -> ReturnPolicy {
            ReturnPolicy(store: store, country: "IT", kind: .storePolicy, days: days, startEvent: .delivery,
                         conditions: ["Prodotto integro e nella confezione originale"], exclusions: ["Prodotti personalizzati"],
                         returnMethods: ["Punto di ritiro", "Corriere a domicilio"], freeReturn: true, source: storeSource,
                         notes: "Dato dimostrativo")
        }

        func item(_ name: String, _ store: String, _ price: String, order: Int, delivery: Int?, status: ReturnStatus = .toEvaluate,
                  policy: Int? = nil, verified: Bool = false) -> Purchase {
            var p = Purchase(productName: name, store: store)
            p.price = Decimal(string: price)
            p.orderDate = day(order)
            p.deliveryDate = delivery.map(day)
            p.orderNumber = "\(abs(name.hashValue) % 900_000 + 100_000)"
            p.source = .demo
            p.createdAt = day(order)
            p.history = [HistoryEntry(date: day(order), kind: .created, message: "Acquisto aggiunto (Demo)")]
            if let policy { p.policies = [storePolicy(store, policy)] }
            p.deadline = DeadlineEngine.proposeDeadline(for: p, storePolicies: p.policies, calendar: cal)
            if let d = p.deadline {
                p.history.append(HistoryEntry(date: day(order), kind: .deadline, message: "Scadenza proposta: \(Formatters.date(d.date)) — \(d.rule)"))
            }
            if verified { p.deadline?.verification = .verified }
            p.status = status
            p.refund.expectedAmount = p.totalPrice
            return p
        }

        var shoes = item("Sneakers in pelle bianche", "Zalando", "89.95", order: -26, delivery: -23, policy: 30, verified: true)
        shoes.notes = "Numero troppo piccolo, provare il 42."
        var headphones = item("Cuffie wireless con cancellazione del rumore", "Amazon", "249.00", order: -14, delivery: -12, status: .toReturn, policy: 30)
        try? ReturnFlow.apply(.requested, to: &headphones, at: day(-1))
        headphones.returnInfo.reference = "RMA-55821"
        let lamp = item("Lampada da tavolo", "IKEA", "39.99", order: -10, delivery: -9)
        var jacket = item("Giacca impermeabile", "Decathlon", "129.00", order: -30, delivery: -27, policy: 30)
        try? ReturnFlow.apply(.shipped, to: &jacket, at: day(-3))
        jacket.returnInfo.carrier = "BRT"
        jacket.returnInfo.trackingNumber = "BRT0042137788"
        try? ReturnFlow.apply(.awaitingRefund, to: &jacket, at: day(-1))
        var phoneCase = item("Custodia per smartphone", "Amazon", "19.99", order: -40, delivery: -38, policy: 30)
        ReturnFlow.confirmRefund(&phoneCase, amount: Decimal(string: "19.99")!, date: day(-8), returnCost: 0)
        phoneCase.status = .refunded
        let mixer = item("Frullatore a immersione", "MediaWorld", "59.90", order: -3, delivery: nil)
        var shirt = item("Camicia di lino", "Zara", "35.95", order: -50, delivery: -47)
        shirt.status = .keep
        let watch = item("Smartwatch sportivo", "Unieuro", "179.00", order: -20, delivery: -19)

        data.purchases = [shoes, headphones, lamp, jacket, phoneCase, mixer, shirt, watch]
        featuredID = headphones.id
        return data
    }
}
