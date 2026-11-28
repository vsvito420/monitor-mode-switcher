# Einrichtungsanleitung für KI-Agenten

Du richtest den **Monitor Mode Switcher** für den Nutzer ein. Alles steht in `config.json` neben
`MonitorModeSwitcher.ps1`. Befehle mit Windows PowerShell 5.1 aus diesem Ordner ausführen.
Der Nutzer spricht Deutsch – antworte auf Deutsch.

## 1. Monitore ermitteln

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\MonitorModeSwitcher.ps1 -List
```

Liefert jeden angeschlossenen Monitor (auch ausgeschaltete):
`id` (EDID-Modellcode – darauf verweisen die Modi), `name`, `active`, `primary`,
`x`, `y`, `width`, `height`, `refresh` (nur bei aktiven Monitoren gefüllt).

Ordne die Worte des Nutzers („der 1440p“, „der Lenovo“, „der 165-Hz-Monitor“) über `name` und Auflösung den `id`s zu.
Ist es nicht eindeutig, frag nach.

## 2. Modi in `config.json` schreiben

```json
{
  "moveWindows": true,
  "settleDelayMs": 3000,
  "modes": [
    { "name": "Schreibtisch", "displays": [
      { "id": "ACR0915", "name": "Acer 1440p", "primary": true,  "x": 0,    "y": 0,   "width": 2560, "height": 1440, "refresh": 0 },
      { "id": "LEN111C", "name": "Lenovo",     "primary": false, "x": 2560, "y": 360, "width": 1920, "height": 1080, "refresh": 0 } ] }
  ]
}
```

Regeln:
- Jeder Modus listet die Monitore, die **an** sein sollen. Alle anderen werden **ausgeschaltet**.
- Genau ein Monitor pro Modus hat `"primary": true`, bei `x: 0, y: 0`.
- Koordinaten sind physische Pixel in einem gemeinsamen virtuellen Desktop. Einen Monitor
  - **rechts** vom Hauptmonitor: `x = Breite des Hauptmonitors`
  - **links** vom Hauptmonitor: `x = -seine Breite`
  - unten bündig: `y = Höhe Hauptmonitor - seine Höhe`; oben bündig: `y = 0`
- Monitore müssen Kante an Kante liegen (keine Lücken, keine Überlappung).
- `width`/`height` muss eine Auflösung sein, die der Monitor kann; ohne andere Angabe die native Auflösung.
- `refresh: 0` = höchste Bildwiederholrate bei dieser Auflösung (empfohlen).
- `"audio"` an einem Modus wird automatisch gelernt: Solange die Tray-App läuft, merkt sich der aktuelle Modus die in
  Windows gewählte Ausgabe und stellt sie beim nächsten Wechsel dorthin wieder her, falls vorhanden.
  Vorbelegen geht auch (Teil des Gerätenamens aus `.\MonitorModeSwitcher.ps1 -Audio`; eine führende Nummer wie
  `"1 - "` weglassen, die kann sich ändern). Leer oder fehlend = Audio nicht anfassen.
- Bestehende Modi behalten, außer der Nutzer will sie entfernt haben. Datei als UTF-8 schreiben.
- Die Schlüssel in `config.json` bleiben englisch (Kompatibilität); nur die Oberfläche ist deutsch.

Alternative: Hat der Nutzer ein Layout schon in Windows angeordnet, mit
`.\MonitorModeSwitcher.ps1 -Capture "Name"` speichern.

## 3. Optionale Einstellungen

- Autostart: Registry-Wert `MonitorModeSwitcher` unter `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` mit
  `"C:\Windows\System32\wscript.exe" "<voller Pfad>\MonitorModeSwitcher.vbs"` (wie die anderen Tools in `C:\Tools`).
  Am einfachsten: Einstellungen → „Mit Windows starten“. Eine alte Verknüpfung `Monitor Mode Switcher.lnk` im
  Autostart-Ordner wird beim Tray-Start automatisch umgestellt.
- Ändert der Nutzer in Windows Anordnung oder Hauptanzeige, übernimmt die App das beim nächsten Wechsel in den
  bisherigen Modus (nur wenn genau dessen Monitore an sind). `startupAction: "last"` stellt beim Start nichts um,
  wenn schon die richtigen Monitore an sind.
- `rememberWindows` (bool, Standard an): Vor jedem Wechsel merkt sich die App die genaue Position jedes Fensters im
  bisherigen Modus (`%APPDATA%\MonitorModeSwitcher\windows.json`) und setzt die Fenster beim Zurückwechseln in diesen
  Modus wieder dorthin. Gilt bis zur Abmeldung (Fenster-Handles); neue Fenster behandelt `moveWindows`.
- `moveWindows` (bool), `settleDelayMs` (500–15000, erhöhen, wenn Fenster falsch landen).
- `startupAction`: `"last"` (`lastMode` herstellen, Standard), `"mode"` (immer `startupMode`), `"none"`.
- `controllerPrompt` (bool) + `controllerMode` (Modusname): Verbindet sich ein Xbox/XInput-Controller und der aktuelle
  Modus ist nicht `controllerMode`, erscheint eine mit dem Controller bedienbare Abfrage.
- `controllerViewA` / `controllerViewB` (Modusname oder `""`): Ansicht halten und 2x A / B tippen schaltet direkt auf
  diesen Modus (kollidiert nicht mit Steam Big Picture / Xbox-Overlay).
- `toggleModes` (Array mit zwei Modusnamen): zwischen diesen wechselt `-Toggle` / `Toggle.vbs`. Leer = die ersten zwei Modi.
- `toggleHotkey` (z. B. `"Ctrl+#"`, `"Ctrl+Alt+F9"`, `""` = aus): globales Tastenkürzel zum Umschalten, solange die Tray-App läuft.
- `lastMode` und `lastSwitch` schreibt die App bei jedem Umschalten selbst; nicht bearbeiten.
- Beim Umbenennen/Löschen eines Modus passt die App alle Verweise (`startupMode`, `controller*`, `toggleModes`) mit an.

## 4. Prüfen

```powershell
.\MonitorModeSwitcher.ps1 -Modes
```

Umschalten (`-Mode "Name"`) schaltet Bildschirme aus/an – **vor dem Testen den Nutzer fragen** und danach auf seinen
bevorzugten Modus zurückschalten. Dann die Tray-App starten: `MonitorModeSwitcher.vbs` doppelklicken / ausführen.
Fehler und Umschaltungen stehen in `%APPDATA%\MonitorModeSwitcher\log.txt`.

## Für Änderungen am Code

- Eine Datei: `MonitorModeSwitcher.ps1` (PowerShell 5.1 + eingebettetes C# über `Add-Type`, C# 5).
- Die Datei ist **UTF-8 mit BOM** gespeichert, sonst liest PowerShell 5.1 die Umlaute falsch. Beim Bearbeiten beibehalten.
- `config.json` wird über eine Temp-Datei ersetzt (`Save-Config`), weil Tray, `Toggle.vbs` und CLI gleichzeitig
  lesen/schreiben können. Umschaltungen sind über den Mutex `Local\MonitorModeSwitcherSwitch` gegeneinander gesperrt.
- Gemeinsame Regeln für alle Tools: [`..\KONVENTIONEN.md`](../KONVENTIONEN.md).
