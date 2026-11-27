# Monitor Mode Switcher

Ein kleines Windows-Tool im Infobereich, das mit einem Klick zwischen gespeicherten Monitor-Layouts umschaltet,
z. B. **Schreibtisch** (1440p-Hauptmonitor + Seitenmonitor rechts) und **Bett/Couch** (TV oder 1080p als Hauptmonitor + Seitenmonitor links).

- Schaltet Monitore an/aus, setzt Hauptmonitor, Position, Auflösung und Bildwiederholrate
- **Nimmt deine Fenster mit**: Fenster auf Monitoren, die an bleiben, bleiben dort. Wird ein Monitor ausgeschaltet,
  wandern seine Fenster auf den neuen Hauptmonitor (wenn er der Hauptmonitor war) oder auf einen Seitenmonitor, der an
  bleibt. Maximierte und randlose Vollbild-Fenster bleiben so.
- **Merkt sich die Audio-Ausgabe pro Modus**: Wählst du in Windows eine andere Ausgabe, merkt sich der aktuelle Modus
  das; beim nächsten Wechsel zurück wird sie wiederhergestellt, falls das Gerät da ist (sonst bleibt Audio unverändert)
- **Merkt sich den letzten Modus** über einen Neustart hinweg oder startet immer in einem festen Modus
- **Xbox-Controller**: **Ansicht** halten und **2x A** oder **2x B** tippen schaltet direkt auf einen gewählten Modus
  (z. B. A = Schreibtisch, B = Bett). Optional kommt beim Verbinden eines Controllers die Frage „auf Bett wechseln?“.
- **Tastenkürzel** `Strg+#` (einstellbar) wechselt zwischen zwei Modi
- Symbol im Infobereich (aktueller Modus ist abgehakt), Einstellungsfenster, Autostart
- Einfache JSON-Konfiguration + Kommandozeile, damit **ein KI-Assistent es für dich einrichten kann** (siehe [AGENTS.md](AGENTS.md))
- Keine Installation, keine Abhängigkeiten – nur PowerShell 5.1, das in Windows 10/11 enthalten ist

## Installation

1. Repo herunterladen (Code → Download ZIP) und dauerhaft entpacken, z. B. nach `C:\Tools\MonitorModeSwitcher`.
2. **`MonitorModeSwitcher.vbs`** doppelklicken. Im Infobereich erscheint ein Monitor-Symbol (ggf. unter `^`).

## Modi einrichten

1. Monitore in **Windows-Einstellungen → System → Anzeige** so anordnen, wie du sie für Modus 1 willst
   (welche Monitore an sind, welcher Hauptmonitor ist, wo sie stehen).
2. Symbol → **Einstellungen… → Aktuelles neu speichern…** → Namen eingeben (z. B. `Schreibtisch`).
3. In den Windows-Anzeigeeinstellungen für Modus 2 umstellen und wieder speichern (z. B. `Bett`).
4. Fertig. Aufs Symbol klicken und einen Modus wählen.

In den Einstellungen gibt es außerdem: Modi umbenennen/überschreiben/löschen, **Mit Windows starten**, Fenster
mitnehmen an/aus und die Wartezeit, bevor Fenster verschoben werden.

### Von einer KI einrichten lassen

Den Ordner in Claude Code (oder einem anderen Coding-Agenten) öffnen und z. B. sagen:

> Richte den Monitor Mode Switcher ein: „Schreibtisch“ = mein 1440p-Monitor als Hauptmonitor mit dem Lenovo rechts,
> „Bett“ = der 1080p-165-Hz-Monitor als Hauptmonitor mit dem Lenovo links. Autostart an.

Der Agent folgt [AGENTS.md](AGENTS.md).

## Kommandozeile

```powershell
.\MonitorModeSwitcher.ps1 -List              # angeschlossene Monitore als JSON
.\MonitorModeSwitcher.ps1 -Modes             # gespeicherte Modi als JSON
.\MonitorModeSwitcher.ps1 -Audio             # Audio-Ausgabegeräte als JSON
.\MonitorModeSwitcher.ps1 -Mode "Schreibtisch"     # umschalten
.\MonitorModeSwitcher.ps1 -Capture "Schreibtisch"  # aktuelles Windows-Layout als Modus speichern
.\MonitorModeSwitcher.ps1 -Delete "Schreibtisch"
.\MonitorModeSwitcher.ps1 -Settings
```

**Ein-Klick-Umschalter in der Taskleiste:** `Toggle.vbs` (oder `MonitorModeSwitcher.ps1 -Toggle`) wechselt zwischen
zwei Modi – `toggleModes` in config.json, sonst die ersten zwei Modi. Eine Verknüpfung auf
`wscript.exe "C:\Pfad\Toggle.vbs"` anlegen, ihr `icon.ico` geben (wird beim ersten Tray-Start erzeugt), ins Startmenü
legen und „An Taskleiste anheften“ wählen.

Tastenkürzel-Tipp: Verknüpfung auf `wscript.exe "C:\Pfad\MonitorModeSwitcher.vbs" "Schreibtisch"` anlegen und in
deren Eigenschaften eine Tastenkombination setzen.

## Probleme?

Rechtsklick aufs Symbol → **Diagnose-Log öffnen** (`%APPDATA%\MonitorModeSwitcher\log.txt`). Dort stehen jede
Umschaltung und alle Fehler.

## Grenzen

- Spiele im **exklusiven** Vollbild lassen sich nicht zuverlässig verschieben – besser randloses Fenster/Vollbild-Fenster.
- Zwei Monitore *desselben Modells* haben dieselbe ID; es wird der zuerst gefundene benutzt.
- Minimierte Fenster überlässt das Tool Windows.

## Lizenz

MIT
