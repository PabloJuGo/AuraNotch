<div align="center">

<img src="Docs/images/icon.png" width="112" alt="Aura Notch Symbol">

# Aura Notch

**Verwandelt den MacBook-Notch in ein nützliches, dezentes Panel.**
Wiedergabesteuerung, eine temporäre Dateiablage, Ihre nächsten Termine, ein Timer, Lautstärke, Akku und Zwischenablage-Verlauf – nur einen Mausklick entfernt.

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [简体中文](README.zh-CN.md)

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift)
![License GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)
![Status beta](https://img.shields.io/badge/status-beta-yellow)

<img src="Docs/images/closed.png" width="420" alt="Geschlossener Notch während der Musikwiedergabe">

</div>

Aura Notch ist eine native macOS-App, geschrieben in Swift (SwiftUI + AppKit) und ohne Abhängigkeiten von Drittanbietern. Sie sitzt im Notch, bleibt unauffällig und öffnet sich zu einem Panel, sobald Sie mit dem Zeiger darüberfahren. Alles läuft lokal: kein Account, keine Analyse, keine Telemetrie.

<div align="center">
<img src="Docs/images/home.png" width="720" alt="Startpanel mit Wiedergabe, Heute, Zwischenablage und Ablage">
</div>

## Funktionen

- **Geschlossener Notch mit Live-Aktivität.** Ein animierter Equalizer und der Titel erscheinen neben dem Notch, solange etwas läuft, ein Timer zeigt seinen Countdown, und kurze Hinweise (anstehender Termin, Ladegerät angeschlossen, Timer beendet) gleiten herein. Die geschlossene Form hat eine feste, symmetrische Breite: Sie wächst nie mit dem Songtitel und verdeckt so wenig wie möglich von Ihrer Menüleiste.
- **Start.** Heutiges Datum und Akku, aktuelle Wiedergabe mit Cover und Steuerung, heutige Termine, letzte Einträge der Zwischenablage und Ihre Ablage – alles auf einen Blick.
- **Medien.** Musik und Spotify: Titel, Interpret, Fortschritt und Vor-/Zurückspulen, Abspielen/Pause/Nächster/Vorheriger im macOS-Stil. Wischen Sie mit zwei Fingern über den geschlossenen Notch, um Titel zu überspringen. Spotify-Cover sind optional und das Einzige, was die App jemals herunterlädt.
- **Ablage.** Ziehen Sie Dateien oder Links zum Notch, und er öffnet sich, um sie aufzunehmen. Die Ablage speichert Verweise und verschiebt oder löscht Ihre Originale nie. Öffnen, im Finder anzeigen, Pfad kopieren, teilen oder per AirDrop senden und Objekte wieder herausziehen. Die Speicherung über Sitzungen hinweg ist optional.
- **Kalender.** Ihre nächsten Termine, nur lesend, über EventKit und mit ausdrücklicher Berechtigung.
- **Widgets.** Timer, Lautstärke, Akku, Datum und Schnellaktionen in einem übersichtlichen zweispaltigen Raster.
- **Zwischenablage-Verlauf (optional).** Text, Links und Bilder, nur im Arbeitsspeicher gehalten. Als vertraulich oder flüchtig markierte Einträge (etwa von Passwortverwaltungen) werden ignoriert; der Verlauf ist ausgeschaltet, bis Sie ihn aktivieren.
- **Designs und Sprachen.** Wählen Sie eine Akzentfarbe und die Größe des geschlossenen Notch. Die Oberfläche ist auf Englisch, Spanisch, Französisch, Deutsch, brasilianischem Portugiesisch und vereinfachtem Chinesisch verfügbar.
- **Gutes Systembürger-Verhalten.** Nicht aktivierendes Panel, das nie den Fokus stiehlt, globaler Kurzbefehl (`⌃⌥N`), Menüleistensymbol, Öffnen beim Anmelden, berücksichtigt *Bewegung reduzieren*, blendet sich über Vollbild-Apps aus (einstellbar) und verbraucht im Ruhezustand rund 0 % CPU.
- **Funktioniert auch ohne Notch.** Auf Macs und Displays ohne Notch wird daraus eine kleine schwebende Pille oben in der Bildschirmmitte.

<div align="center">
<img src="Docs/images/media.png" width="360" alt="Medienpanel"> <img src="Docs/images/clipboard.png" width="360" alt="Zwischenablage-Panel">
</div>

## Installation

1. Laden Sie `AuraNotch.zip` vom [neuesten Release](https://github.com/PabloJuGo/AuraNotch/releases/latest) herunter und entpacken Sie die Datei.
2. Ziehen Sie **AuraNotch.app** in Ihren Programme-Ordner.
3. Beim ersten Mal: **Rechtsklick > Öffnen** und bestätigen. Die App ist ad hoc signiert, aber nicht notarisiert (für die Notarisierung ist ein kostenpflichtiger Apple-Entwickler-Account nötig), daher bittet macOS einmalig um Ihre Zustimmung. Wenn macOS sie dennoch ablehnt, führen Sie Folgendes aus:
   ```sh
   xattr -dr com.apple.quarantine /Applications/AuraNotch.app
   ```
4. Suchen Sie den Notch-Streifen oben am Bildschirm (und das Symbol in der Menüleiste). Fahren Sie mit dem Zeiger darüber, klicken Sie darauf oder drücken Sie `⌃⌥N`.

**Voraussetzungen:** macOS 14 oder neuer. Entwickelt und getestet wurde auf einem MacBook mit Notch unter macOS 27; andere Konfigurationen sollten funktionieren, wurden aber weniger getestet.

## Einstellungen

Öffnen Sie die **Einstellungen** über das Zahnrad in der Kopfzeile des Panels oder über das Menüleistensymbol.

| Bereich | Was Sie ändern können |
|---|---|
| Allgemein | Öffnen beim Anmelden, Anzeigemodus, **Sprache der Benutzeroberfläche**, Akzentfarbe, Größe des geschlossenen Notch |
| Interaktion | Öffnen beim Darüberfahren, per Klick oder mit dem globalen Kurzbefehl; Verzögerung beim Darüberfahren; Verhalten im Vollbild; Titel im geschlossenen Notch; Wischen zum Überspringen; Hinweise |
| Animationen | Bewegung (dem System folgen, reduziert oder keine) |
| Module | Start, Medien, Ablage, Kalender, Widgets und Zwischenablage aktivieren, deaktivieren und neu anordnen |
| Datenschutz | Ablage zwischen Sitzungen behalten, Verlaufslimit, Spotify-Cover, alle Daten löschen |

Eine Sprachänderung wird nach einem Neustart wirksam; die App bietet dafür die Schaltfläche **Jetzt neustarten** an.

## Datenschutz und Berechtigungen

- Kein Account, keine Analyse, keine Telemetrie, keine Update-Prüfungen.
- **Netzwerk:** Die einzige Anfrage betrifft das Spotify-Coverbild, und zwar von der Adresse, die Spotify selbst bereitstellt. Sie können sie unter Einstellungen → Datenschutz ausschalten.
- **Berechtigungen werden nur angefragt, wenn Sie die Funktion nutzen, die sie benötigt:** *Automation*, um Musik und Spotify zu steuern (das Anzeigen des aktuellen Titels braucht keine Berechtigung), und *Kalender*, um Ihre Termine aufzulisten (nur lesend).
- Die Ablage speichert Verweise auf Ihre Dateien, der Zwischenablage-Verlauf liegt nur im Arbeitsspeicher, und **Einstellungen → Datenschutz → Alle Daten löschen** entfernt alles.

Mehr Details in [PRIVACY.md](PRIVACY.md) und [SECURITY.md](SECURITY.md) (beide vorerst auf Spanisch).

## Aus dem Quellcode bauen

Sie benötigen nur die Swift-6-Toolchain (die Xcode Command Line Tools genügen).

```sh
git clone https://github.com/PabloJuGo/AuraNotch.git
cd AuraNotch
swift build
swift run AuraSelfTests            # test suite with detailed failures
swift run AuraNotch                # run without packaging (no Calendar/Automation prompts)
Scripts/package-app.sh             # builds dist/AuraNotch.app (release, ad-hoc signed)
```

Nützliche Flags: `--skip-onboarding`, `--start-module=<home|media|shelf|calendar|widgets|clipboard>`.

Hinweise zur Architektur finden Sie in [ARCHITECTURE.md](ARCHITECTURE.md), Designentscheidungen in [Docs/decisions](Docs/decisions) (Spanisch).

## Status und bekannte Einschränkungen

Aura Notch ist eine **Beta**. Gut zu wissen:

- Nicht notarisiert (siehe Installation). Es gibt kein automatisches Update.
- Die Abläufe für Kalender und AirDrop hängen von Systemberechtigungen und -dialogen ab und wurden auf echter Hardware nur begrenzt getestet.
- Externe Displays, mehrere Displays und VoiceOver wurden kaum praktisch getestet.
- Die Automation-Berechtigungsabfrage von Spotify erscheint unter aktuellen macOS-Versionen mitunter verzögert; macOS fragt dann beim ersten Drücken einer Steuertaste nach.
- Übersetzungen außer Englisch und Spanisch wurden mit maschineller Unterstützung erstellt und nicht von Muttersprachlern geprüft. Korrekturen sind sehr willkommen.
- Einige Projektdokumente (Architekturhinweise, Entscheidungen, Datenschutz) sind noch auf Spanisch.

## Mitwirken

Issues und Pull Requests sind willkommen; siehe [CONTRIBUTING.md](CONTRIBUTING.md). Um eine Übersetzung zu korrigieren oder hinzuzufügen, bearbeiten Sie `Resources/<language>.lproj/Localizable.strings` und führen Sie `Scripts/check-localizations.py` aus.

## Lizenz

[GPL-3.0](LICENSE). Aura Notch ist ein unabhängiges Projekt und steht in keiner Verbindung zu Apple, Spotify oder anderen hier erwähnten Apps.
