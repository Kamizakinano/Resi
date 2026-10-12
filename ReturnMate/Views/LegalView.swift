import SwiftUI

struct LegalView: View {
    enum Page { case privacy, terms, retention }
    let page: Page

    var body: some View {
        ScrollView {
            Text(.init(text))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        switch page {
        case .privacy: return "Privacy"
        case .terms: return "Condizioni d'uso"
        case .retention: return "Conservazione dei dati"
        }
    }

    private var text: String {
        switch page {
        case .privacy:
            return """
            **Informativa sulla privacy**

            ReturnMate raccoglie solo i dati necessari al suo funzionamento: il nome e l'email (facoltativa) del profilo, i dati degli acquisti che inserisci (prodotto, negozio, prezzo, date, numero d'ordine, note), le immagini che alleghi e le tue preferenze.

            **Dove sono salvati.** Tutti i dati restano su questo iPhone, nello spazio riservato all'app, protetti dalla cifratura di iOS (sono illeggibili quando il telefono è bloccato). La chiave API dell'AI è conservata nel Portachiavi del dispositivo. Non esiste un server ReturnMate e non ci sono strumenti di tracciamento o pubblicità.

            **Intelligenza artificiale.** Solo se configuri una chiave API e scegli di usare l'AI, le immagini o i testi che importi, e il nome del negozio quando cerchi una politica di reso, vengono inviati ad Anthropic per l'elaborazione, secondo le condizioni del tuo account Anthropic. Senza AI l'analisi avviene interamente sul dispositivo.

            **Link.** Quando importi un link, l'app scarica la pagina indicata direttamente dal sito del negozio.

            **I tuoi diritti.** Puoi esportare i dati (CSV/PDF), modificare o eliminare singoli acquisti ed eliminare l'intero account da Impostazioni: l'eliminazione è immediata e definitiva.
            """
        case .terms:
            return """
            **Condizioni d'uso**

            ReturnMate è uno strumento di promemoria. Le scadenze calcolate dall'app sono **proposte** finché non le verifichi con la fonte indicata; anche una scadenza verificata può cambiare se il negozio aggiorna le proprie condizioni.

            Le informazioni sulle politiche di reso possono essere trovate con una ricerca automatica: controlla sempre la fonte ufficiale del negozio. Il diritto di recesso legale (14 giorni per gli acquisti a distanza nell'UE) è distinto dalla politica commerciale del negozio e dalla garanzia legale per prodotti difettosi.

            L'app non contatta i negozi per tuo conto e non verifica automaticamente i rimborsi: un rimborso è considerato ricevuto solo quando lo confermi.

            ReturnMate non fornisce consulenza legale.
            """
        case .retention:
            return """
            **Conservazione dei dati**

            I dati restano sul dispositivo finché non li elimini. Gli acquisti archiviati vengono conservati e possono essere ripristinati in qualsiasi momento.

            Eliminando un acquisto vengono cancellati anche i suoi allegati e la sua cronologia. Eliminando l'account vengono cancellati profilo, acquisti, allegati, impostazioni e chiave API.

            Se usi i backup di iCloud o del computer, i dati dell'app possono essere inclusi nel backup del dispositivo secondo le impostazioni di iOS.

            I file esportati (CSV/PDF) sono temporanei: dove li salvi o condividi dipende da te.
            """
        }
    }
}
