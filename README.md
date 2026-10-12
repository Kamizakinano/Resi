# ReturnMate

App iOS (SwiftUI, iOS 17+) per tenere traccia di acquisti, scadenze di reso, promemoria e rimborsi.

## Build

Il progetto Xcode è generato con [XcodeGen](https://github.com/yonaskolb/XcodeGen) da `project.yml`:

```sh
brew install xcodegen
xcodegen generate
open ReturnMate.xcodeproj
```

La GitHub Action `.github/workflows/ios.yml` esegue i test sul simulatore, genera gli screenshot e produce
`ReturnMate.ipa` non firmato (da firmare e installare con Sideloadly), pubblicandoli sul branch `builds`.

## Struttura

- `ReturnMate/Models` — modelli dati (acquisti, scadenze, politiche, reso, rimborso)
- `ReturnMate/Services` — calcolo e verifica scadenze, flusso del reso, promemoria, statistiche,
  persistenza cifrata, OCR, client AI (Anthropic Messages API), esportazione
- `ReturnMate/Views` — interfaccia SwiftUI
- `ReturnMateTests` — test unitari
