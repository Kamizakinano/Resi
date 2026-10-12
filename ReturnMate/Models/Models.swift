import Foundation

// MARK: - Stato del reso

enum ReturnStatus: String, Codable, CaseIterable, Identifiable {
    case toEvaluate
    case keep
    case toReturn
    case requested
    case authorized
    case packed
    case shipped
    case awaitingRefund
    case refunded
    case closed

    var id: String { rawValue }

    /// Posizione nel flusso (1...9). "Da tenere" e "Da restituire" condividono il passo 2.
    var step: Int {
        switch self {
        case .toEvaluate: return 1
        case .keep, .toReturn: return 2
        case .requested: return 3
        case .authorized: return 4
        case .packed: return 5
        case .shipped: return 6
        case .awaitingRefund: return 7
        case .refunded: return 8
        case .closed: return 9
        }
    }

    var title: String {
        switch self {
        case .toEvaluate: return "Da valutare"
        case .keep: return "Da tenere"
        case .toReturn: return "Da restituire"
        case .requested: return "Reso richiesto"
        case .authorized: return "Reso autorizzato"
        case .packed: return "Pacco preparato"
        case .shipped: return "Spedito"
        case .awaitingRefund: return "In attesa di rimborso"
        case .refunded: return "Rimborso ricevuto"
        case .closed: return "Chiuso"
        }
    }

    var symbol: String {
        switch self {
        case .toEvaluate: return "questionmark.circle"
        case .keep: return "hand.thumbsup"
        case .toReturn: return "arrow.uturn.backward.circle"
        case .requested: return "envelope"
        case .authorized: return "checkmark.seal"
        case .packed: return "shippingbox"
        case .shipped: return "truck.box"
        case .awaitingRefund: return "hourglass"
        case .refunded: return "eurosign.circle"
        case .closed: return "lock"
        }
    }

    /// Stati in cui il reso è "in corso" (dopo la decisione di restituire, prima del rimborso).
    var isReturnInProgress: Bool {
        [.requested, .authorized, .packed, .shipped, .awaitingRefund].contains(self)
    }

    /// La scadenza del reso è ancora rilevante: l'utente deve ancora agire entro la data.
    var deadlineMatters: Bool {
        [.toEvaluate, .toReturn, .requested, .authorized, .packed].contains(self)
    }

    /// Gli stati in cui il prodotto è (o sarà) restituito.
    var isReturnPath: Bool {
        step >= 3 && self != .closed || self == .toReturn
    }
}

// MARK: - Politiche e scadenze

enum PolicyKind: String, Codable, CaseIterable, Identifiable {
    case legalWithdrawal
    case storePolicy
    case warranty
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .legalWithdrawal: return "Diritto di recesso (legge)"
        case .storePolicy: return "Politica del negozio"
        case .warranty: return "Garanzia legale (difetti)"
        case .manual: return "Inserita manualmente"
        }
    }
}

enum StartEvent: String, Codable, CaseIterable, Identifiable {
    case delivery
    case order

    var id: String { rawValue }

    var title: String {
        switch self {
        case .delivery: return "dalla consegna"
        case .order: return "dall'ordine"
        }
    }
}

enum VerificationState: String, Codable {
    case proposed
    case verified

    var title: String {
        switch self {
        case .proposed: return "Proposta"
        case .verified: return "Verificata"
        }
    }
}

enum PurchaseChannel: String, Codable, CaseIterable, Identifiable {
    case online
    case inStore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .online: return "Online"
        case .inStore: return "In negozio"
        }
    }
}

struct PolicySource: Codable, Hashable {
    var url: String
    var title: String
    var lastChecked: Date
    /// La fonte proviene dal sito ufficiale del negozio o da una fonte normativa ufficiale.
    var isOfficial: Bool
    /// L'URL compariva davvero tra i risultati della ricerca (o è una fonte normativa nota).
    var seenInSearchResults: Bool

    var host: String? { URL(string: url)?.host?.lowercased() }
}

struct ReturnPolicy: Codable, Hashable {
    var store: String
    var country: String
    var kind: PolicyKind
    var days: Int?
    var startEvent: StartEvent
    var conditions: [String] = []
    var exclusions: [String] = []
    var returnMethods: [String] = []
    var freeReturn: Bool?
    var source: PolicySource?
    var notes: String = ""
}

struct Deadline: Codable, Hashable {
    /// Ultimo giorno utile (inizio giornata nel fuso orario dell'utente).
    var date: Date
    var kind: PolicyKind
    var startEvent: StartEvent
    /// Data dell'evento da cui decorre il termine (consegna o ordine).
    var startDate: Date?
    var days: Int?
    var verification: VerificationState = .proposed
    var source: PolicySource?
    /// Descrizione della regola applicata (es. "14 giorni dalla consegna, art. 52 Codice del Consumo").
    var rule: String
    /// Il termine è stato prorogato perché cadeva di sabato/domenica.
    var extendedForWeekend: Bool = false
    var manuallyEdited: Bool = false
    var warnings: [String] = []
    /// Negozio e paese per cui vale la politica (per il controllo di pertinenza).
    var policyStore: String?
    var policyCountry: String?
}

// MARK: - Reso e rimborso

struct ReturnInfo: Codable, Hashable {
    var requestDate: Date?
    var reference: String = ""
    var carrier: String = ""
    var trackingNumber: String = ""
    /// Data di consegna del pacco al corriere.
    var shippedDate: Date?
    var notes: String = ""
}

struct RefundInfo: Codable, Hashable {
    var expectedAmount: Decimal?
    var receivedAmount: Decimal?
    var receivedDate: Date?
    var returnCost: Decimal?
    /// Il rimborso viene considerato ricevuto solo dopo conferma esplicita dell'utente.
    var confirmedByUser: Bool = false

    var netRecovered: Decimal? {
        guard confirmedByUser, let received = receivedAmount else { return nil }
        return received - (returnCost ?? 0)
    }
}

// MARK: - Allegati e cronologia

enum AttachmentKind: String, Codable, CaseIterable {
    case productPhoto
    case receipt
    case screenshot
    case document

    var title: String {
        switch self {
        case .productPhoto: return "Foto prodotto"
        case .receipt: return "Ricevuta"
        case .screenshot: return "Screenshot"
        case .document: return "Documento"
        }
    }
}

struct Attachment: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var kind: AttachmentKind
    var fileName: String
    var createdAt: Date = Date()

    var isImage: Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "heic"].contains(ext)
    }
}

enum HistoryKind: String, Codable {
    case created, edited, status, deadline, verification, refund, archive, attachment, policy, note
}

struct HistoryEntry: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var date: Date = Date()
    var kind: HistoryKind
    var message: String
}

enum InputSource: String, Codable {
    case manual, photo, screenshot, emailText, link, demo

    var title: String {
        switch self {
        case .manual: return "Manuale"
        case .photo: return "Foto"
        case .screenshot: return "Screenshot"
        case .emailText: return "Testo email"
        case .link: return "Link"
        case .demo: return "Demo"
        }
    }
}

// MARK: - Acquisto

struct Purchase: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    /// Prodotti dello stesso ordine condividono lo stesso orderGroup.
    var orderGroup: UUID = UUID()
    var productName: String
    var store: String
    var storeCountry: String = "IT"
    var channel: PurchaseChannel = .online
    var price: Decimal?
    var currency: String = "EUR"
    var quantity: Int = 1
    var orderDate: Date?
    var deliveryDate: Date?
    var orderNumber: String = ""
    var productURL: String = ""
    var orderURL: String = ""
    var notes: String = ""
    var imageAttachmentID: UUID?
    var attachments: [Attachment] = []
    var deadline: Deadline?
    var policies: [ReturnPolicy] = []
    var needsManualDeadline: Bool = false
    var status: ReturnStatus = .toEvaluate
    var returnInfo = ReturnInfo()
    var refund = RefundInfo()
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var history: [HistoryEntry] = []
    var source: InputSource = .manual

    var totalPrice: Decimal? {
        guard let price else { return nil }
        return price * Decimal(quantity)
    }

    var legalWarrantyEnd: Date? {
        guard let start = deliveryDate ?? orderDate else { return nil }
        return Calendar(identifier: .gregorian).date(byAdding: .year, value: 2, to: start)
    }

    mutating func log(_ kind: HistoryKind, _ message: String, at date: Date = Date()) {
        history.append(HistoryEntry(date: date, kind: kind, message: message))
        updatedAt = date
    }
}

// MARK: - Profilo e impostazioni

struct UserProfile: Codable, Hashable {
    var name: String
    var email: String
    var createdAt: Date = Date()
}

struct AppSettings: Codable, Hashable {
    var currency: String = "EUR"
    var timeZoneID: String = TimeZone.current.identifier
    var reminderOffsets: [Int] = [7, 3, 1, 0]
    var reminderHour: Int = 9
    var reminderMinute: Int = 0
    var verifyReminders: Bool = true
    var appLock: Bool = false
    var aiModel: String = "claude-opus-5-5"
    var aiScansThisMonth: Int = 0
    var aiScansMonth: String = ""
    var defaultCountry: String = "IT"

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = Locale(identifier: "it_IT")
        return cal
    }
}

struct AppData: Codable {
    var schemaVersion: Int = 1
    var profile: UserProfile?
    var purchases: [Purchase] = []
    var settings = AppSettings()
    var policyCache: [String: [ReturnPolicy]] = [:]
}
