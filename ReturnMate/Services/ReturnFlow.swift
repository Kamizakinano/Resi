import Foundation

/// Regole di transizione tra gli stati del reso.
enum ReturnFlow {

    enum TransitionError: Error, Equatable, LocalizedError {
        case notAllowed(from: ReturnStatus, to: ReturnStatus)
        case refundNotConfirmed

        var errorDescription: String? {
            switch self {
            case let .notAllowed(from, to):
                return "Non è possibile passare da \"\(from.title)\" a \"\(to.title)\"."
            case .refundNotConfirmed:
                return "Conferma l'importo ricevuto prima di segnare il rimborso come ricevuto."
            }
        }
    }

    /// Stati raggiungibili. Si può saltare in avanti; non si torna indietro (usa "Annulla ultimo cambio").
    static func allowedTargets(from status: ReturnStatus) -> [ReturnStatus] {
        ReturnStatus.allCases.filter { canTransition(from: status, to: $0) }
    }

    static func canTransition(from: ReturnStatus, to: ReturnStatus) -> Bool {
        if from == to { return false }
        switch from {
        case .closed:
            return false
        case .keep:
            // Un prodotto tenuto può tornare "da restituire" (ripensamento) oppure essere chiuso.
            return to == .toReturn || to == .closed
        case .toReturn:
            return to == .keep || to.step > from.step
        default:
            if to == .keep { return from == .toEvaluate }
            return to.step > from.step
        }
    }

    /// Applica la transizione registrando la cronologia e i dati collegati.
    static func apply(_ to: ReturnStatus, to purchase: inout Purchase, at date: Date = Date()) throws {
        let from = purchase.status
        guard canTransition(from: from, to: to) else { throw TransitionError.notAllowed(from: from, to: to) }
        if to == .refunded && !purchase.refund.confirmedByUser {
            throw TransitionError.refundNotConfirmed
        }
        let skipped = ReturnStatus.allCases.filter {
            $0.step > from.step && $0.step < to.step && $0 != .keep && $0 != .toReturn
        }
        if to == .requested && purchase.returnInfo.requestDate == nil {
            purchase.returnInfo.requestDate = date
        }
        if to == .shipped && purchase.returnInfo.shippedDate == nil {
            purchase.returnInfo.shippedDate = date
        }
        purchase.status = to
        var msg = "Stato: \(from.title) → \(to.title)"
        if !skipped.isEmpty {
            msg += " (saltati: \(skipped.map(\.title).joined(separator: ", ")))"
        }
        purchase.log(.status, msg, at: date)
    }

    /// Ripristina lo stato precedente registrato nella cronologia.
    static func undoLast(_ purchase: inout Purchase, at date: Date = Date()) -> Bool {
        guard let last = purchase.history.last(where: { $0.kind == .status }), last.message.hasPrefix("Stato: ") else { return false }
        let body = last.message.dropFirst("Stato: ".count)
        guard let fromTitle = body.components(separatedBy: " → ").first,
              let previous = ReturnStatus.allCases.first(where: { $0.title == fromTitle }) else { return false }
        let current = purchase.status
        purchase.status = previous
        if current == .refunded { purchase.refund.confirmedByUser = false }
        purchase.log(.status, "Annullato cambio di stato: \(current.title) → \(previous.title)", at: date)
        return true
    }

    /// Conferma la ricezione del rimborso (solo su azione esplicita dell'utente).
    static func confirmRefund(_ purchase: inout Purchase, amount: Decimal, date: Date, returnCost: Decimal?) {
        purchase.refund.receivedAmount = amount
        purchase.refund.receivedDate = date
        purchase.refund.returnCost = returnCost
        purchase.refund.confirmedByUser = true
        purchase.log(.refund, "Rimborso confermato: \(Formatters.money(amount, currency: purchase.currency))", at: date)
    }
}
