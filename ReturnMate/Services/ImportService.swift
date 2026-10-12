import Foundation
import UIKit

/// Legge una pagina web e ne ricava titolo, metadati prodotto e testo visibile.
enum LinkFetcher {
    struct Page {
        var url: URL
        var title: String?
        var price: Decimal?
        var currency: String?
        var jsonLD: [String]
        var text: String
    }

    static func fetch(_ urlString: String) async throws -> Page {
        guard let url = URL(string: PurchaseValidator.normalizedURL(urlString)), PurchaseValidator.isValidWebURL(url.absoluteString) else {
            throw AIError.invalidResponse("link non valido")
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("it-IT,it;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        let finalURL = response.url ?? url
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return parse(html: html, url: finalURL)
    }

    static func parse(html: String, url: URL) -> Page {
        func meta(_ name: String) -> String? {
            let patterns = [
                #"<meta[^>]+(?:property|name)=["']\#(name)["'][^>]+content=["']([^"']*)["']"#,
                #"<meta[^>]+content=["']([^"']*)["'][^>]+(?:property|name)=["']\#(name)["']"#,
            ]
            for p in patterns {
                if let m = HeuristicParser.matches(p, in: html).first, let v = m.last, !v.isEmpty { return decodeEntities(v) }
            }
            return nil
        }
        let title = meta("og:title") ?? HeuristicParser.matches(#"<title[^>]*>([^<]*)</title>"#, in: html).first?.last.map(decodeEntities)
        let priceString = meta("product:price:amount") ?? meta("og:price:amount")
        let currency = meta("product:price:currency") ?? meta("og:price:currency")
        let jsonLD = HeuristicParser.matches(#"<script[^>]+application/ld\+json[^>]*>([\s\S]*?)</script>"#, in: html).compactMap { $0.last }
        var text = html
        for p in [#"<script[\s\S]*?</script>"#, #"<style[\s\S]*?</style>"#, #"<noscript[\s\S]*?</noscript>"#, #"<[^>]+>"#] {
            text = HeuristicParser.regex(p).stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        text = decodeEntities(text)
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return Page(url: url, title: title?.nilIfEmpty, price: priceString.flatMap(Formatters.parseDecimal),
                    currency: currency?.uppercased(), jsonLD: jsonLD, text: text)
    }

    static func decodeEntities(_ s: String) -> String {
        var r = s
        for (k, v) in ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&euro;": "€"] {
            r = r.replacingOccurrences(of: k, with: v)
        }
        return r
    }

    /// Contesto da passare all'AI. Le pagine lunghe vengono accorciate e lo si dichiara esplicitamente.
    static func context(for page: Page, limit: Int = 40_000) -> String {
        var parts = ["URL: \(page.url.absoluteString)"]
        if let t = page.title { parts.append("Titolo: \(t)") }
        if !page.jsonLD.isEmpty { parts.append("Dati strutturati (JSON-LD):\n" + page.jsonLD.joined(separator: "\n").prefix(15_000)) }
        if page.text.count > limit {
            parts.append("Testo visibile (primi \(limit) caratteri di \(page.text.count), il resto è stato omesso):\n" + page.text.prefix(limit))
        } else {
            parts.append("Testo visibile:\n" + page.text)
        }
        return parts.joined(separator: "\n\n")
    }
}

enum ImportInput {
    case images([UIImage], InputSource)
    case text(String)
    case link(String)
}

/// Coordina l'importazione: AI se configurata e disponibile, altrimenti estrazione locale.
/// Se l'AI fallisce, si ripiega sull'estrazione locale e lo si segnala.
@MainActor
enum ImportService {

    static func process(_ input: ImportInput, store: DataStore, useAI: Bool) async -> ExtractionDraft {
        let settings = store.settings
        let client = useAI && store.aiScansRemaining > 0 ? ClaudeClient.fromKeychain(model: settings.aiModel) : nil
        var aiNote: String?
        if useAI && client == nil {
            aiNote = Keychain.get(ClaudeClient.keychainKey) == nil
                ? "AI non configurata: dati estratti sul dispositivo."
                : "Scansioni AI esaurite per questo mese: dati estratti sul dispositivo."
        }

        switch input {
        case let .images(images, source):
            if let client {
                do {
                    var d = try await client.extractPurchase(images: images, text: nil, pageContext: nil, today: Date())
                    d.source = source
                    store.registerAIScan()
                    return d
                } catch {
                    aiNote = "AI non disponibile (\(error.localizedDescription)): dati estratti sul dispositivo."
                }
            }
            var text = ""
            for image in images {
                text += ((try? await OCRService.recognizeText(in: image)) ?? "") + "\n"
            }
            var d = HeuristicParser.parse(text, source: source, timeZone: settings.timeZone, defaultCountry: settings.defaultCountry)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { d.warnings.insert("Nessun testo leggibile nell'immagine.", at: 0) }
            if let aiNote { d.warnings.insert(aiNote, at: 0) }
            return d

        case let .text(text):
            if let client {
                do {
                    var d = try await client.extractPurchase(images: [], text: text, pageContext: nil, today: Date())
                    d.source = .emailText
                    store.registerAIScan()
                    return d
                } catch {
                    aiNote = "AI non disponibile (\(error.localizedDescription)): dati estratti sul dispositivo."
                }
            }
            var d = HeuristicParser.parse(text, source: .emailText, timeZone: settings.timeZone, defaultCountry: settings.defaultCountry)
            if let aiNote { d.warnings.insert(aiNote, at: 0) }
            return d

        case let .link(link):
            let page: LinkFetcher.Page
            do {
                page = try await LinkFetcher.fetch(link)
            } catch {
                var d = ExtractionDraft()
                d.source = .link
                d.items[0].productURL = PurchaseValidator.normalizedURL(link)
                if let host = URL(string: PurchaseValidator.normalizedURL(link))?.host {
                    d = applyHost(host, to: d)
                }
                d.warnings = ["Impossibile leggere la pagina (\(error.localizedDescription)). Completa i dati a mano."]
                return d
            }
            if let client {
                do {
                    var d = try await client.extractPurchase(images: [], text: nil, pageContext: LinkFetcher.context(for: page), today: Date())
                    d.source = .link
                    if d.items.count == 1 && d.items[0].productURL.isEmpty { d.items[0].productURL = page.url.absoluteString }
                    store.registerAIScan()
                    return d
                } catch {
                    aiNote = "AI non disponibile (\(error.localizedDescription)): dati letti dalla pagina."
                }
            }
            var d = ExtractionDraft()
            d.source = .link
            d = applyHost(page.url.host ?? "", to: d)
            d.items[0].name = page.title ?? ""
            d.items[0].price = page.price
            d.items[0].productURL = page.url.absoluteString
            if let c = page.currency { d.currency = c }
            if page.title == nil { d.warnings.append("Nome del prodotto non trovato nella pagina.") }
            if page.price == nil { d.warnings.append("Prezzo non trovato nella pagina.") }
            d.warnings.append("Le date d'ordine e di consegna non sono presenti in una pagina prodotto: inseriscile.")
            if let aiNote { d.warnings.insert(aiNote, at: 0) }
            return d
        }
    }

    static func applyHost(_ host: String, to draft: ExtractionDraft) -> ExtractionDraft {
        var d = draft
        let h = host.lowercased().replacingOccurrences(of: "www.", with: "")
        if let known = HeuristicParser.knownStores.first(where: { s in s.keys.contains { h.contains($0.replacingOccurrences(of: " ", with: "")) } }) {
            d.store = known.name
        } else {
            let parts = h.split(separator: ".")
            if parts.count >= 2 { d.store = String(parts[parts.count - 2]).capitalized }
        }
        if let tld = h.split(separator: ".").last, let c = HeuristicParser.tldCountry[String(tld)] { d.storeCountry = c }
        return d
    }
}

/// Ricerca della politica di reso con l'AI; senza AI restano il recesso legale e l'inserimento manuale.
@MainActor
enum PolicyService {
    static func research(for purchaseID: UUID, store: DataStore) async -> String {
        guard let p = store.purchase(purchaseID) else { return "" }
        guard let client = ClaudeClient.fromKeychain(model: store.settings.aiModel) else {
            return AIError.missingKey.localizedDescription + " Puoi inserire la scadenza manualmente."
        }
        store.researchInProgress.insert(purchaseID)
        defer { store.researchInProgress.remove(purchaseID) }
        do {
            let products = store.purchases.filter { $0.store == p.store }.map(\.productName)
            let result = try await client.researchPolicy(store: p.store, country: p.storeCountry,
                                                         products: Array(Set(products)).sorted(), today: Date())
            store.applyResearch(result.policies, store: p.store, country: p.storeCountry)
            store.mutate(purchaseID) { item in
                if result.insufficient { item.needsManualDeadline = true }
            }
            var msg = result.message.isEmpty ? "Ricerca completata." : result.message
            if result.insufficient { msg += " Informazioni insufficienti: inserisci o conferma la scadenza manualmente." }
            return msg
        } catch {
            return "Ricerca non riuscita: \(error.localizedDescription) I dati inseriti restano disponibili."
        }
    }
}
