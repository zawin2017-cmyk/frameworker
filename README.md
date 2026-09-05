# Frameworker

Vensterbeheer voor macOS met één toetscombinatie. Houd Control en Option ingedrukt, druk een
toets, en het voorste venster springt naar de linkerhelft, een kwart, het midden of een vaste
maat. Gemaakt als licht alternatief voor Rectangle: een menubalk-app zonder dock-icoon die
alleen wakker wordt wanneer je een sneltoets indrukt.

## Standaardsneltoetsen

Alles met ⌃⌥ (Control + Option), tenzij anders vermeld. De indeling volgt Rectangle, zodat
spiergeheugen meeverhuist.

| Actie | Toets | | Actie | Toets |
|---|---|---|---|---|
| Linkerhelft | ← | | Eerste derde | D |
| Rechterhelft | → | | Middelste derde | F |
| Bovenste helft | ↑ | | Laatste derde | G |
| Onderste helft | ↓ | | Eerste tweederde | E |
| Linksboven | U | | Laatste tweederde | T |
| Rechtsboven | I | | Maximaliseren | ↩ |
| Linksonder | J | | Centreren | C |
| Rechtsonder | K | | Vaste maat | V |
| Kleiner | - | | Herstellen | ⌫ |
| Groter | = | | Naar volgend scherm | ⌃⌥⌘ → |
| Bijna maximaliseren | (geen) | | Naar vorig scherm | ⌃⌥⌘ ← |
| Instellingen openen | , | | | |

Nog een keer dezelfde toets drukken schakelt door. Eerste derde loopt naar rechts (eerste,
middelste, laatste derde), laatste derde loopt naar links, tweederde springt naar de andere kant,
en een linker- of rechterhelft wordt bij herhalen tweederde en daarna een derde aan dezelfde kant.
Dat gaat op basis van waar het venster nu staat, dus een handmatig verschoven venster begint
gewoon weer bij de eerste stap.

Elke combinatie is aan te passen in het instellingenvenster (menubalkicoon, Instellingen…):
klik op een veld en druk de nieuwe combinatie in. Escape annuleert, Backspace maakt een veld
leeg. Een combinatie die al bij een andere actie hoort, wordt daar losgemaakt. Staat een pil
oranje, dan heeft een andere app (bijvoorbeeld een nog draaiende Rectangle) die combinatie al
geclaimd.

De vaste maat stel je in hetzelfde venster in, standaard 1280 bij 800 px, gecentreerd op het
scherm waar het venster op staat. Herstellen zet een venster terug naar waar het stond vóór de
eerste actie erop.

## Installeren

Vereist macOS 14 of nieuwer en de Xcode Command Line Tools (`xcode-select --install`).
Xcode zelf is niet nodig.

```bash
./build.sh --install
```

Dat bouwt de app met SwiftPM, zet hem in `~/Applications/Frameworker.app` en start hem. Zonder
`--install` blijft de bundel in de verborgen map `.build/`, zodat Spotlight en Alfred maar één
Frameworker kennen. Start je toch een tweede exemplaar, dan geeft dat het stokje door aan het
draaiende exemplaar en opent daar het instellingenvenster. Bij de
eerste start vraagt macOS om toegang tot Toegankelijkheid; zet Frameworker aan onder
Systeeminstellingen, Privacy en beveiliging, Toegankelijkheid. Zonder die toestemming kan geen
enkele app vensters van andere apps verplaatsen.

De app wordt ad hoc gesigneerd met een designated requirement op de bundle-identifier, zodat
de toestemming ook na een nieuwe build blijft staan. Mocht macOS na een update toch weigeren,
dan helpt dit:

```bash
tccutil reset Accessibility nl.zawin.frameworker
```

Starten bij inloggen zet je aan via het menubalkicoon of het instellingenvenster. Het
instellingenvenster is ook zonder menubalkicoon te bereiken: met ⌃⌥, of door de app nog eens te
starten (Alfred, Spotlight, dubbelklik).

### Zonder menubalkicoon

Op macOS 26 kun je menubalkiconen van apps per app uitzetten (Systeeminstellingen, Menubalk).
Frameworker heeft het icoon niet nodig: de sneltoetsen werken los ervan, en het instellingenvenster
open je met ⌃⌥, of door de app nog eens te starten. Bij elke start schrijft Frameworker één regel
naar `~/Library/Logs/Frameworker.log` met de positie die de menubalk aan het icoon gaf; `placed
false` betekent dat het icoon verborgen is. Een overzicht van alle apps met een menubalk-item:

```bash
swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("nl.zawin.frameworker.diagnose"), object: nil, userInfo: nil, deliverImmediately: true)' && sleep 2 && tail -12 ~/Library/Logs/Frameworker.log
```

## Zuinig

- Sneltoetsen lopen via Carbon `RegisterEventHotKey`: het systeem wekt de app alleen bij een
  geregistreerde combinatie. Geen event tap, geen toetsenbordmonitor, geen timers.
- Vensters worden verplaatst via de Accessibility API, alleen op het moment van een actie.
- Pure AppKit, geen SwiftUI. Het instellingenvenster bestaat alleen zolang het open is.
- In rust: circa 11 MB fysiek geheugen (`footprint`), 0% CPU, geen GPU-werk. Gemeten op macOS 26.

## Projectopbouw

| Bestand | Doet |
|---|---|
| `Sources/Frameworker/Layout.swift` | Alle geometrie, zonder AppKit, getest in `Tests/` |
| `Sources/Frameworker/WindowManager.swift` | Accessibility: voorste venster ophalen en verplaatsen |
| `Sources/Frameworker/HotKeyCenter.swift` | Globale sneltoetsen via Carbon |
| `Sources/Frameworker/Settings.swift` | UserDefaults: sneltoetsen en vaste maat |
| `Sources/Frameworker/SettingsWindowController.swift` | Instellingenvenster (donker, Liquid Glass op macOS 26) |
| `Sources/Frameworker/ShortcutRecorderView.swift` | Het veld waarin je een combinatie indrukt |
| `Sources/Frameworker/AppDelegate.swift` | Menubalkicoon en menu |
| `scripts/make-icon.swift` | Tekent het app-icoon en pakt het in als .icns |
| `build.sh` | Bouwt, bundelt, signeert en installeert |
| `Frameworker --snapshot pad.png` | Ontwikkelhulp: opent het instellingenvenster, schrijft er een PNG van en stopt |
| `test.sh` | Draait de tests, ook met alleen de Command Line Tools |

Tests draaien met `./test.sh` (een kale `swift test` vindt Testing.framework niet zonder Xcode).

## Licentie

MIT, zie `LICENSE`.
