import Foundation
import UIKit

enum Exporter {

    static func csvField(_ s: String) -> String {
        if s.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" || $0 == "," }) {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    /// CSV con separatore ";" (compatibile con Excel in italiano).
    static func csv(_ purchases: [Purchase], timeZone: TimeZone) -> String {
        let header = ["Prodotto", "Negozio", "Paese", "Canale", "Prezzo", "Quantità", "Valuta", "Data ordine", "Data consegna",
                      "Numero ordine", "Stato", "Scadenza", "Tipo scadenza", "Verifica", "Regola", "Fonte", "Ultima verifica fonte",
                      "Rif. reso", "Corriere", "Tracking", "Data spedizione", "Rimborso previsto", "Rimborso ricevuto",
                      "Data rimborso", "Costo reso", "Archiviato", "Note", "Link prodotto", "Link ordine"]
        var rows = [header.joined(separator: ";")]
        for p in purchases {
            let d = p.deadline
            let fields: [String] = [
                p.productName, p.store, p.storeCountry, p.channel.title, Formatters.decimalString(p.price), String(p.quantity), p.currency,
                Formatters.isoDay(p.orderDate, timeZone: timeZone), Formatters.isoDay(p.deliveryDate, timeZone: timeZone),
                p.orderNumber, p.status.title, Formatters.isoDay(d?.date, timeZone: timeZone), d?.kind.title ?? "",
                d?.verification.title ?? "", d?.rule ?? "", d?.source?.url ?? "", Formatters.isoDay(d?.source?.lastChecked, timeZone: timeZone),
                p.returnInfo.reference, p.returnInfo.carrier, p.returnInfo.trackingNumber,
                Formatters.isoDay(p.returnInfo.shippedDate, timeZone: timeZone), Formatters.decimalString(p.refund.expectedAmount),
                p.refund.confirmedByUser ? Formatters.decimalString(p.refund.receivedAmount) : "",
                Formatters.isoDay(p.refund.receivedDate, timeZone: timeZone), Formatters.decimalString(p.refund.returnCost),
                p.isArchived ? "Sì" : "No", p.notes, p.productURL, p.orderURL,
            ]
            rows.append(fields.map(csvField).joined(separator: ";"))
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    static func writeCSV(_ purchases: [Purchase], timeZone: TimeZone) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ReturnMate-acquisti.csv")
        // BOM UTF-8 per la corretta lettura degli accenti in Excel.
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(csv(purchases, timeZone: timeZone).utf8)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func writePDF(_ purchases: [Purchase], summary: StatsSummary, currency: String, timeZone: TimeZone) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ReturnMate-report.pdf")
        let page = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let margin: CGFloat = 40
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 20)]
        let headAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 11)]
        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10)]
        let smallAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray]

        try renderer.writePDF(to: url) { ctx in
            var y: CGFloat = margin
            func newPageIfNeeded(_ h: CGFloat) {
                if y + h > page.height - margin {
                    ctx.beginPage()
                    y = margin
                }
            }
            func draw(_ s: String, _ attrs: [NSAttributedString.Key: Any], height: CGFloat = 14) {
                newPageIfNeeded(height)
                (s as NSString).draw(in: CGRect(x: margin, y: y, width: page.width - margin * 2, height: height * 3), withAttributes: attrs)
                y += height
            }
            ctx.beginPage()
            draw("ReturnMate — Report acquisti", titleAttrs, height: 28)
            draw("Generato il \(Formatters.dateTime(Date(), timeZone: timeZone))", smallAttrs, height: 20)
            draw("Totale acquisti: \(Formatters.money(summary.totalPurchased, currency: currency))", bodyAttrs)
            draw("Valore ancora restituibile: \(Formatters.money(summary.returnableValue, currency: currency))", bodyAttrs)
            draw("Rimborsi attesi: \(Formatters.money(summary.refundsExpected, currency: currency))", bodyAttrs)
            draw("Rimborsi ricevuti: \(Formatters.money(summary.refundsReceived, currency: currency)) — recuperato netto: \(Formatters.money(summary.netRecovered, currency: currency))", bodyAttrs)
            draw("Resi completati: \(summary.completedReturns) — Scadenze superate: \(summary.missedDeadlines)", bodyAttrs, height: 26)

            for p in purchases {
                newPageIfNeeded(70)
                draw("\(p.productName) — \(p.store)", headAttrs, height: 16)
                draw("Prezzo: \(Formatters.money(p.totalPrice, currency: p.currency))  ·  Ordine: \(Formatters.date(p.orderDate, timeZone: timeZone))  ·  Consegna: \(Formatters.date(p.deliveryDate, timeZone: timeZone))", bodyAttrs)
                if let d = p.deadline {
                    draw("Scadenza: \(Formatters.date(d.date, timeZone: timeZone)) (\(d.verification.title.lowercased())) — \(d.rule)", bodyAttrs)
                    if let s = d.source { draw("Fonte: \(s.url)", smallAttrs) }
                } else {
                    draw("Scadenza: non determinata", bodyAttrs)
                }
                draw("Stato: \(p.status.title)\(p.refund.confirmedByUser ? " — Rimborso: \(Formatters.money(p.refund.receivedAmount, currency: p.currency))" : "")", bodyAttrs, height: 22)
            }
        }
        return url
    }
}
