import Foundation

/// Calcolo e verifica delle scadenze di reso. Tutte le funzioni sono pure e testabili.
enum DeadlineEngine {

    static let euCountries: Set<String> = [
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE",
        "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE",
        // SEE: la direttiva 2011/83/UE si applica anche a Islanda, Liechtenstein, Norvegia
        "IS", "LI", "NO",
    ]

    static let legalSourceURL = "https://eur-lex.europa.eu/legal-content/IT/TXT/?uri=CELEX:32011L0083"

    /// Diritto di recesso UE per contratti a distanza: 14 giorni dalla consegna (art. 9 dir. 2011/83/UE,
    /// art. 52 Codice del Consumo in Italia).
    static func legalWithdrawalPolicy(country: String, checkedAt: Date = Date()) -> ReturnPolicy? {
        guard euCountries.contains(country.uppercased()) else { return nil }
        return ReturnPolicy(
            store: "*",
            country: country.uppercased(),
            kind: .legalWithdrawal,
            days: 14,
            startEvent: .delivery,
            conditions: [
                "Vale per acquisti online o a distanza da venditori professionali.",
                "Il termine decorre dal giorno successivo alla consegna del bene.",
            ],
            exclusions: [
                "Beni personalizzati o deperibili",
                "Prodotti sigillati aperti per motivi igienici o di protezione della salute",
                "Contenuti digitali già scaricati con consenso",
            ],
            returnMethods: ["Comunicazione di recesso al venditore entro il termine"],
            freeReturn: nil,
            source: PolicySource(
                url: legalSourceURL,
                title: "Direttiva 2011/83/UE sui diritti dei consumatori (EUR-Lex)",
                lastChecked: checkedAt,
                isOfficial: true,
                seenInSearchResults: true
            ),
            notes: "Diritto previsto dalla legge, distinto dalla politica commerciale del negozio e dalla garanzia per difetti."
        )
    }

    /// Ultimo giorno utile: inizio giornata di (giorno evento + days).
    static func computeDate(start: Date, days: Int, kind: PolicyKind, calendar: Calendar) -> (date: Date, extended: Bool) {
        let startDay = calendar.startOfDay(for: start)
        var end = calendar.date(byAdding: .day, value: days, to: startDay) ?? startDay
        var extended = false
        // Reg. (CEE) 1182/71 art. 3.4: un termine legale che scade di sabato o domenica
        // si estende al primo giorno lavorativo successivo.
        if kind == .legalWithdrawal {
            while calendar.isDateInWeekend(end) {
                end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
                extended = true
            }
        }
        return (end, extended)
    }

    /// Calcola la scadenza proposta per una politica. Non inventa la data di inizio: se manca la
    /// data richiesta usa l'altra disponibile e lo segnala tra gli avvisi.
    static func deadline(for purchase: Purchase, policy: ReturnPolicy, calendar: Calendar) -> Deadline? {
        guard let days = policy.days, days > 0 else { return nil }
        var warnings: [String] = []
        let start: Date
        switch policy.startEvent {
        case .delivery:
            if let d = purchase.deliveryDate {
                start = d
            } else if let o = purchase.orderDate {
                start = o
                warnings.append("Data di consegna mancante: calcolo provvisorio a partire dalla data dell'ordine.")
            } else {
                return nil
            }
        case .order:
            guard let o = purchase.orderDate else { return nil }
            start = o
        }
        let (date, extended) = computeDate(start: start, days: days, kind: policy.kind, calendar: calendar)
        var rule = "\(days) giorni \(policy.startEvent.title)"
        switch policy.kind {
        case .legalWithdrawal: rule += " (diritto di recesso UE, dir. 2011/83/UE)"
        case .storePolicy: rule += " (politica di \(policy.store))"
        case .warranty: rule += " (garanzia)"
        case .manual: break
        }
        if extended { rule += ", prorogato al primo giorno lavorativo" }
        if policy.kind == .legalWithdrawal {
            warnings.append("Le festività nazionali non sono considerate nel calcolo.")
        }
        return Deadline(
            date: date,
            kind: policy.kind,
            startEvent: policy.startEvent,
            startDate: start,
            days: days,
            verification: .proposed,
            source: policy.source,
            rule: rule,
            extendedForWeekend: extended,
            manuallyEdited: false,
            warnings: warnings,
            policyStore: policy.store,
            policyCountry: policy.country
        )
    }

    /// Le politiche applicabili all'acquisto (il recesso legale vale solo per acquisti online nell'UE).
    static func applicablePolicies(for purchase: Purchase, storePolicies: [ReturnPolicy]) -> [ReturnPolicy] {
        var result: [ReturnPolicy] = storePolicies.filter { $0.kind == .storePolicy && ($0.days ?? 0) > 0 }
        if purchase.channel == .online, let legal = legalWithdrawalPolicy(country: purchase.storeCountry) {
            result.append(legal)
        }
        return result
    }

    /// Sceglie la scadenza più favorevole all'utente tra quelle calcolabili.
    static func proposeDeadline(for purchase: Purchase, storePolicies: [ReturnPolicy], calendar: Calendar) -> Deadline? {
        let candidates = applicablePolicies(for: purchase, storePolicies: storePolicies)
            .compactMap { deadline(for: purchase, policy: $0, calendar: calendar) }
        // A parità di data preferisce la fonte del negozio, che di solito descrive anche le modalità.
        return candidates.max { a, b in
            if a.date != b.date { return a.date < b.date }
            return a.kind == .legalWithdrawal && b.kind == .storePolicy
        }
    }

    // MARK: - Verifica

    enum VerificationIssue: String, CaseIterable, Equatable {
        case missingSource = "Manca la fonte."
        case invalidSourceURL = "Il link della fonte non è valido."
        case sourceNotOfficial = "La fonte non risulta ufficiale."
        case sourceNotFound = "La fonte non è stata trovata tra i risultati della ricerca."
        case notRelevant = "La politica si riferisce a un altro negozio o paese."
        case missingRule = "La regola applicata non è documentata."
        case missingStartDate = "Manca la data da cui decorre il termine."
        case startDateMismatch = "La data di inizio non corrisponde all'evento previsto dalla regola."
        case calculationMismatch = "Il calcolo della data non corrisponde alla regola."
        case channelNotApplicable = "Il recesso legale non si applica agli acquisti in negozio."
    }

    static func normalizeStore(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let cleaned = folded.lowercased()
            .replacingOccurrences(of: "www.", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        for suffix in ["com", "it", "de", "fr", "es", "eu", "couk", "shop", "store"] where cleaned.hasSuffix(suffix) && cleaned.count > suffix.count + 2 {
            return String(cleaned.dropLast(suffix.count))
        }
        return cleaned
    }

    /// Controlla tutte le condizioni necessarie per contrassegnare la scadenza come verificata.
    static func verificationIssues(for deadline: Deadline, purchase: Purchase, calendar: Calendar) -> [VerificationIssue] {
        var issues: [VerificationIssue] = []

        if let source = deadline.source {
            if let url = URL(string: source.url), let scheme = url.scheme?.lowercased(),
               ["http", "https"].contains(scheme), url.host != nil {
                // ok
            } else {
                issues.append(.invalidSourceURL)
            }
            if !source.isOfficial { issues.append(.sourceNotOfficial) }
            if !source.seenInSearchResults { issues.append(.sourceNotFound) }
        } else {
            issues.append(.missingSource)
        }

        if deadline.rule.trimmingCharacters(in: .whitespaces).isEmpty || deadline.days == nil {
            issues.append(.missingRule)
        }

        switch deadline.kind {
        case .legalWithdrawal:
            if purchase.channel != .online { issues.append(.channelNotApplicable) }
            if let c = deadline.policyCountry, c.uppercased() != purchase.storeCountry.uppercased() {
                issues.append(.notRelevant)
            }
        case .storePolicy, .manual, .warranty:
            if let store = deadline.policyStore, store != "*" {
                if normalizeStore(store) != normalizeStore(purchase.store) { issues.append(.notRelevant) }
            }
            if let c = deadline.policyCountry, !c.isEmpty, c.uppercased() != purchase.storeCountry.uppercased() {
                issues.append(.notRelevant)
            }
        }

        let expectedStart: Date? = deadline.startEvent == .delivery ? purchase.deliveryDate : purchase.orderDate
        if let expectedStart {
            if let start = deadline.startDate {
                if !calendar.isDate(start, inSameDayAs: expectedStart) { issues.append(.startDateMismatch) }
                if let days = deadline.days {
                    let recomputed = computeDate(start: start, days: days, kind: deadline.kind, calendar: calendar).date
                    if !calendar.isDate(recomputed, inSameDayAs: deadline.date) { issues.append(.calculationMismatch) }
                }
            } else {
                issues.append(.missingStartDate)
            }
        } else {
            issues.append(.missingStartDate)
        }

        var seen = Set<VerificationIssue>()
        return issues.filter { seen.insert($0).inserted }
    }

    static func canVerify(_ deadline: Deadline, purchase: Purchase, calendar: Calendar) -> Bool {
        verificationIssues(for: deadline, purchase: purchase, calendar: calendar).isEmpty
    }

    /// Giorni rimanenti (negativi se scaduta). 0 = scade oggi.
    static func daysRemaining(until date: Date, now: Date, calendar: Calendar) -> Int {
        let a = calendar.startOfDay(for: now)
        let b = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }
}
