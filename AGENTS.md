# Setup guide for AI agents

You are configuring **Monitor Mode Switcher** for the user. Everything lives in `config.json`
next to `MonitorModeSwitcher.ps1`. Run commands with Windows PowerShell 5.1 from this folder.

## 1. Discover monitors

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\MonitorModeSwitcher.ps1 -List
```

Returns every connected monitor (also ones that are currently off):
`id` (EDID model code — this is what modes reference), `name`, `active`, `primary`,
`x`, `y`, `width`, `height`, `refresh` (only filled for active monitors).

Match the user's words ("the 1440p one", "the Lenovo", "the 165 Hz monitor") to `id`s using
`name` and resolution. If it's ambiguous, ask the user.

## 2. Write modes into `config.json`

```json
{
  "moveWindows": true,
  "settleDelayMs": 3000,
  "modes": [
    { "name": "Desk", "displays": [
      { "id": "ACR0915", "name": "Acer 1440p", "primary": true,  "x": 0,    "y": 0,   "width": 2560, "height": 1440, "refresh": 0 },
      { "id": "LEN111C", "name": "Lenovo",     "primary": false, "x": 2560, "y": 360, "width": 1920, "height": 1080, "refresh": 0 } ] }
  ]
}
```

Rules:
- Each mode lists the monitors that should be **on**. Every other monitor is turned **off**.
- Exactly one display per mode has `"primary": true`, at `x: 0, y: 0`.
- Coordinates are physical pixels in one virtual desktop. Put a monitor
  - **right** of the primary: `x = primaryWidth`
  - **left** of the primary: `x = -itsWidth`
  - bottom-aligned: `y = primaryHeight - itsHeight`; top-aligned: `y = 0`
- Monitors must touch edge to edge (no gaps, no overlaps).
- `width`/`height` must be a resolution the monitor supports; use its native resolution unless told otherwise.
- `refresh: 0` = highest refresh rate available at that resolution (recommended).
- Optional `"audio"` on a mode: part of the output device name to make default when switching
  (list them with `.\MonitorModeSwitcher.ps1 -Audio`; drop a leading `"1 - "` number, it can change).
  Empty or missing = don't touch audio.
- Keep existing modes unless the user asks to remove them. Write the file as UTF-8.

Alternative: if the user has already arranged a layout in Windows, save it with
`.\MonitorModeSwitcher.ps1 -Capture "Name"`.

## 3. Optional settings

- Autostart: create a shortcut in `shell:startup` (`[Environment]::GetFolderPath('Startup')`)
  named `Monitor Mode Switcher.lnk`, target `wscript.exe`, argument `"<full path>\MonitorModeSwitcher.vbs"`.
- `moveWindows` (bool), `settleDelayMs` (500–15000, raise it if windows land wrong).
- `startupAction`: `"last"` (restore `lastMode`, default), `"mode"` (always `startupMode`), `"none"`.
- `controllerPrompt` (bool) + `controllerMode` (mode name): when an Xbox/XInput controller connects
  and the current mode isn't `controllerMode`, show a controller-navigable prompt.
- `controllerMenuCombo` (bool): tapping View + Menu on the controller opens the mode menu.
- `controllerHoldMode` (mode name or `""`): holding View + Menu for 1 s switches straight to this mode.
- `toggleModes` (array of two mode names): what `-Toggle` / `Toggle.vbs` switches between.
  Empty = the first two modes.
- `lastMode` is written by the app on every switch; don't edit it.

## 4. Verify

```powershell
.\MonitorModeSwitcher.ps1 -Modes
```

Switching (`-Mode "Name"`) turns screens off/on — **ask the user before testing it**, and switch
back to their preferred mode afterwards. Then start the tray app: double-click / run
`MonitorModeSwitcher.vbs`.
