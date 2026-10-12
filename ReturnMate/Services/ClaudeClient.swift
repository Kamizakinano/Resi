import Foundation
import UIKit

enum AIError: LocalizedError {
    case missingKey
    case http(Int, String)
    case refusal
    case truncated
    case invalidResponse(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Configura la chiave API di Claude nelle Impostazioni per usare l'AI."
        case let .http(code, msg):
            switch code {
            case 401: return "Chiave API non valida (401)."
            case 429: return "Troppe richieste: riprova tra poco (429)."
            case 529, 500...599: return "Servizio AI temporaneamente non disponibile (\(code))."
            default: return "Errore AI \(code): \(msg)"
            }
        case .refusal: return "L'AI ha rifiutato la richiesta."
        case .truncated: return "Risposta dell'AI incompleta."
        case let .invalidResponse(m): return "Risposta dell'AI non valida: \(m)"
        case let .network(m): return "Errore di rete: \(m)"
        }
    }
}

/// Client minimale per la Messages API di Anthropic (HTTP diretto: non esiste un SDK Swift ufficiale).
struct ClaudeClient {
    static let keychainKey = "anthropic_api_key"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    var apiKey: String
    var model: String

    static func fromKeychain(model: String) -> ClaudeClient? {
        guard let key = Keychain.get(keychainKey), !key.isEmpty else { return nil }
        return ClaudeClient(apiKey: key, model: model)
    }

    /// I modelli che supportano il fallback lato server in caso di rifiuto.
    private var supportsFallback: Bool {
        ["claude-opus-5-5", "claude-opus-5", "claude-fable-5-1", "claude-sonnet-5-5"].contains(model)
    }

    func send(_ body: [String: Any], timeout: TimeInterval = 180) async throws -> [String: Any] {
        var body = body
        body["model"] = model
        var request = URLRequest(url: Self.endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if supportsFallback {
            body["fallbacks"] = "default"
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200, let json else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw AIError.http(status, message)
        }
        if json["stop_reason"] as? String == "refusal" { throw AIError.refusal }
        return json
    }

    static func texts(_ message: [String: Any]) -> [String] {
        ((message["content"] as? [[String: Any]]) ?? []).compactMap { block in
            block["type"] as? String == "text" ? block["text"] as? String : nil
        }
    }

    static func imageBlock(_ image: UIImage) -> [String: Any]? {
        let resized = image.resized(maxDimension: 1568)
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return nil }
        return ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]]
    }

    /// Estrae il primo oggetto JSON da un testo (anche se racchiuso in ```json ... ```).
    static func extractJSONObject(_ text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        let slice = text[start...end]
        return (try? JSONSerialization.jsonObject(with: Data(slice.utf8))) as? [String: Any]
    }

    func ping() async throws {
        _ = try await send([
            "max_tokens": 64,
            "output_config": ["effort": "low"],
            "messages": [["role": "user", "content": "Rispondi solo: ok"]],
        ], timeout: 60)
    }
}

// MARK: - Estrazione acquisti

extension ClaudeClient {

    static let extractionSchema: [String: Any] = {
        func nullable(_ type: String, _ description: String) -> [String: Any] {
            ["type": [type, "null"], "description": description]
        }
        let item: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "name": ["type": "string", "description": "Nome del prodotto come appare nel documento"],
                "unit_price": nullable("number", "Prezzo unitario pagato, senza simbolo di valuta"),
                "quantity": ["type": "integer", "description": "Quantità (1 se non indicata)"],
                "product_url": nullable("string", "Link al prodotto se presente"),
            ],
            "required": ["name", "unit_price", "quantity", "product_url"],
        ]
        return [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "store": nullable("string", "Nome commerciale del negozio/venditore"),
                "store_country": nullable("string", "Paese del negozio, codice ISO 3166-1 alpha-2 (es. IT), dedotto dal dominio o dall'indirizzo"),
                "channel": ["type": "string", "enum": ["online", "in_store", "unknown"]],
                "order_number": nullable("string", "Numero d'ordine"),
                "order_date": nullable("string", "Data dell'ordine in formato YYYY-MM-DD"),
                "delivery_date": nullable("string", "Data di consegna effettiva (non stimata) in formato YYYY-MM-DD"),
                "currency": nullable("string", "Codice valuta ISO 4217"),
                "order_url": nullable("string", "Link alla pagina dell'ordine se presente"),
                "items": ["type": "array", "items": item],
                "warnings": ["type": "array", "items": ["type": "string"],
                             "description": "Dati ambigui, illeggibili o mancanti, in italiano"],
            ],
            "required": ["store", "store_country", "channel", "order_number", "order_date", "delivery_date",
                         "currency", "order_url", "items", "warnings"],
        ]
    }()

    static let extractionSystem = """
    Estrai i dati di un acquisto da ricevute, screenshot, email di conferma o pagine prodotto.
    Regole:
    - Riporta solo informazioni presenti nel materiale fornito. Se un dato manca o è illeggibile usa null e \
    aggiungi un avviso in "warnings". Non stimare prezzi, date o numeri d'ordine.
    - Una data di consegna "prevista" o "stimata" non è una data di consegna: lasciala null e segnalalo.
    - Se una data numerica può essere letta sia come giorno/mese che mese/giorno, scegli in base al paese \
    del negozio e aggiungi un avviso.
    - Elenca ogni prodotto distinto dell'ordine come elemento separato di "items".
    - Gli avvisi sono in italiano, brevi.
    """

    func extractPurchase(images: [UIImage], text: String?, pageContext: String?, today: Date) async throws -> ExtractionDraft {
        var content: [[String: Any]] = images.compactMap(Self.imageBlock)
        var prompt = "Data di oggi: \(Formatters.isoDay(today)).\n"
        if let text, !text.isEmpty { prompt += "\nTesto fornito dall'utente:\n<testo>\n\(text)\n</testo>\n" }
        if let pageContext, !pageContext.isEmpty { prompt += "\nContenuto della pagina web:\n<pagina>\n\(pageContext)\n</pagina>\n" }
        if !images.isEmpty { prompt += "\nAnalizza le immagini allegate." }
        content.append(["type": "text", "text": prompt])

        let response = try await send([
            "max_tokens": 8000,
            "system": Self.extractionSystem,
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": Self.extractionSchema],
            ],
            "messages": [["role": "user", "content": content]],
        ])
        if response["stop_reason"] as? String == "max_tokens" { throw AIError.truncated }
        guard let text = Self.texts(response).joined().nilIfEmpty, let obj = Self.extractJSONObject(text) else {
            throw AIError.invalidResponse("JSON mancante")
        }
        return Self.draft(from: obj)
    }

    static func draft(from obj: [String: Any]) -> ExtractionDraft {
        var d = ExtractionDraft()
        d.usedAI = true
        d.store = obj["store"] as? String ?? ""
        d.storeCountry = (obj["store_country"] as? String)?.uppercased().nilIfEmpty ?? "IT"
        switch obj["channel"] as? String {
        case "in_store": d.channel = .inStore
        default: d.channel = .online
        }
        d.orderNumber = obj["order_number"] as? String ?? ""
        d.orderDate = Formatters.parseISODay(obj["order_date"] as? String)
        d.deliveryDate = Formatters.parseISODay(obj["delivery_date"] as? String)
        d.currency = (obj["currency"] as? String)?.uppercased().nilIfEmpty ?? "EUR"
        d.orderURL = obj["order_url"] as? String ?? ""
        let items = (obj["items"] as? [[String: Any]]) ?? []
        d.items = items.map { i in
            ExtractedItem(
                name: i["name"] as? String ?? "",
                price: decimal(i["unit_price"]),
                quantity: max(1, (i["quantity"] as? Int) ?? 1),
                productURL: i["product_url"] as? String ?? ""
            )
        }
        if d.items.isEmpty {
            d.items = [ExtractedItem()]
            d.warnings.append("Nessun prodotto riconosciuto.")
        }
        d.warnings += (obj["warnings"] as? [String]) ?? []
        if (obj["channel"] as? String) == "unknown" {
            d.warnings.append("Non è chiaro se l'acquisto sia online o in negozio: impostato come online.")
        }
        return d
    }

    static func decimal(_ any: Any?) -> Decimal? {
        guard let n = any as? NSNumber else { return nil }
        // Arrotonda a 2 decimali per evitare artefatti della virgola mobile.
        return Decimal(string: String(format: "%.2f", n.doubleValue), locale: Locale(identifier: "en_US_POSIX"))
    }
}

// MARK: - Ricerca politiche di reso

struct PolicyResearchResult {
    var policies: [ReturnPolicy]
    var insufficient: Bool
    var message: String
    var warrantyNotes: String?
}

extension ClaudeClient {

    static let researchSystem = """
    Cerchi le condizioni di reso ufficiali di un negozio per un paese specifico, usando la ricerca web.
    - Privilegia il sito ufficiale del negozio per quel paese (pagine "Resi", "Condizioni di vendita", "Aiuto").
    - Distingui: (1) diritto di recesso previsto dalla legge, (2) politica commerciale del negozio, \
    (3) garanzia per prodotti difettosi. Riporta in "store_policy" solo la politica commerciale del negozio.
    - Indica il numero di giorni e da quale evento decorrono (consegna o ordine) solo se la fonte lo dice \
    esplicitamente; altrimenti usa null.
    - "source_url" deve essere un URL effettivamente restituito dalla ricerca. Non inventare URL.
    - Se le informazioni non sono sufficienti, imposta "insufficient_information" a true.
    Rispondi alla fine SOLO con un oggetto JSON con questa struttura:
    {"store_policy": {"days": int|null, "start_event": "delivery"|"order"|null, "conditions": [string], \
    "exclusions": [string], "return_methods": [string], "free_return": bool|null, "source_url": string|null, \
    "source_title": string|null, "source_is_official_store_site": bool, "notes": string} | null, \
    "warranty_notes": string|null, "insufficient_information": bool, "message": string}
    Testi in italiano.
    """

    func researchPolicy(store: String, country: String, products: [String], today: Date) async throws -> PolicyResearchResult {
        let user = """
        Negozio: \(store)
        Paese: \(country)
        Prodotti: \(products.joined(separator: "; "))
        Data di oggi: \(Formatters.isoDay(today))
        Trova la politica di reso attuale del negozio per questo paese.
        """
        var messages: [[String: Any]] = [["role": "user", "content": user]]
        var seenURLs = Set<String>()
        var final: [String: Any]?

        for _ in 0..<4 {
            let response = try await send([
                "max_tokens": 16000,
                "system": Self.researchSystem,
                "output_config": ["effort": "medium"],
                "tools": [["type": "web_search_20260209", "name": "web_search", "max_uses": 6]],
                "messages": messages,
            ], timeout: 300)
            for block in (response["content"] as? [[String: Any]]) ?? [] where block["type"] as? String == "web_search_tool_result" {
                if let results = block["content"] as? [[String: Any]] {
                    results.compactMap { $0["url"] as? String }.forEach { seenURLs.insert($0) }
                }
            }
            if response["stop_reason"] as? String == "pause_turn" {
                // Il server ha sospeso un turno lungo: si continua inviando il contenuto così com'è.
                messages.append(["role": "assistant", "content": response["content"] ?? [Any]()])
                continue
            }
            final = response
            break
        }
        guard let final else { throw AIError.truncated }
        guard let obj = Self.extractJSONObject(Self.texts(final).last ?? "") ?? Self.extractJSONObject(Self.texts(final).joined()) else {
            throw AIError.invalidResponse("risultato della ricerca non leggibile")
        }
        return Self.researchResult(from: obj, store: store, country: country, seenURLs: seenURLs, now: today)
    }

    static func researchResult(from obj: [String: Any], store: String, country: String, seenURLs: Set<String>, now: Date) -> PolicyResearchResult {
        var policies: [ReturnPolicy] = []
        var insufficient = obj["insufficient_information"] as? Bool ?? true
        var message = obj["message"] as? String ?? ""
        if let sp = obj["store_policy"] as? [String: Any] {
            var source: PolicySource?
            if let url = sp["source_url"] as? String, !url.isEmpty {
                let seen = seenURLs.contains { normalizedURL($0) == normalizedURL(url) }
                source = PolicySource(url: url, title: sp["source_title"] as? String ?? url, lastChecked: now,
                                      isOfficial: sp["source_is_official_store_site"] as? Bool ?? false,
                                      seenInSearchResults: seen)
                if !seen { message += " Attenzione: la fonte indicata non compare tra i risultati della ricerca." }
            }
            let days = sp["days"] as? Int
            let start: StartEvent = (sp["start_event"] as? String) == "order" ? .order : .delivery
            if days == nil || sp["start_event"] == nil || sp["start_event"] is NSNull { insufficient = true }
            policies.append(ReturnPolicy(
                store: store, country: country.uppercased(), kind: .storePolicy, days: days, startEvent: start,
                conditions: sp["conditions"] as? [String] ?? [], exclusions: sp["exclusions"] as? [String] ?? [],
                returnMethods: sp["return_methods"] as? [String] ?? [], freeReturn: sp["free_return"] as? Bool,
                source: source, notes: sp["notes"] as? String ?? ""
            ))
        }
        return PolicyResearchResult(policies: policies, insufficient: insufficient,
                                    message: message.trimmingCharacters(in: .whitespaces),
                                    warrantyNotes: obj["warranty_notes"] as? String)
    }

    /// Confronta gli URL ignorando schema, "www.", frammento e barra finale.
    static func normalizedURL(_ s: String) -> String {
        var t = s.lowercased()
        if let hash = t.firstIndex(of: "#") { t = String(t[..<hash]) }
        for prefix in ["https://", "http://"] where t.hasPrefix(prefix) { t = String(t.dropFirst(prefix.count)) }
        if t.hasPrefix("www.") { t = String(t.dropFirst(4)) }
        while t.hasSuffix("/") { t = String(t.dropLast()) }
        return t
    }
}

extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
