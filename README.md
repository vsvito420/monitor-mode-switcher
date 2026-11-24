# Monitor Mode Switcher

A tiny Windows tray tool that switches between saved multi-monitor layouts with one click
— e.g. **Desk** (1440p main + side monitor on the right) and **Bed/Couch** (TV or 1080p main + side monitor on the left).

- Turns monitors on/off, sets primary, positions, resolution and refresh rate
- **Moves your windows along**: windows on monitors that stay on keep their monitor. If a monitor is
  turned off, its windows go to the new primary (if it was the primary) or to a side monitor that
  stays on (if it was a side monitor). Maximized and borderless-fullscreen windows stay that way.
- **Remembers the last mode** after reboot, or always starts in a default mode of your choice
- **Xbox controller**: asks "switch to Bed?" when a controller connects — answer with the
  D-pad/stick + A/B. Tap **View + Menu** anytime to open the mode menu, or **hold them for 1 s**
  to switch straight to a mode you choose (e.g. Desk).
- Tray icon (current mode is checked), settings window, autostart option
- Plain JSON config + CLI, so an **AI assistant can set it up for you** (see [AGENTS.md](AGENTS.md))
- No install, no dependencies — just PowerShell 5.1, which ships with Windows 10/11

## Install

1. Download this repo (Code → Download ZIP) and unzip it somewhere permanent, e.g. `C:\Tools\MonitorModeSwitcher`.
2. Double-click **`MonitorModeSwitcher.vbs`**. A monitor icon appears in the tray (check the `^` overflow).

## Set up your modes

1. Arrange your monitors in **Windows Settings → System → Display** the way you want for mode 1
   (which monitors are on, which is primary, where they sit).
2. Tray icon → **Settings… → Save current as new…** → give it a name (e.g. `Desk`).
3. Rearrange in Windows display settings for mode 2, save again (e.g. `Bed`).
4. Done. Click the tray icon and pick a mode.

Settings also has: rename/overwrite/delete modes, **Start with Windows**, toggle window moving,
and the wait time before windows are moved.

### Let an AI do it

Open this folder in Claude Code (or any coding agent) and say something like:

> Set up Monitor Mode Switcher: "Desk" = my 1440p monitor as main with the Lenovo to the right,
> "Bed" = the 1080p 165 Hz monitor as main with the Lenovo to the left. Enable autostart.

The agent follows [AGENTS.md](AGENTS.md).

## Command line

```powershell
.\MonitorModeSwitcher.ps1 -List              # connected monitors as JSON
.\MonitorModeSwitcher.ps1 -Modes             # saved modes as JSON
.\MonitorModeSwitcher.ps1 -Mode "Desk"       # switch
.\MonitorModeSwitcher.ps1 -Capture "Desk"    # save the current Windows layout as a mode
.\MonitorModeSwitcher.ps1 -Delete "Desk"
.\MonitorModeSwitcher.ps1 -Settings
```

Hotkey tip: create a shortcut to `wscript.exe "C:\path\MonitorModeSwitcher.vbs" "Desk"`, then set a
shortcut key in its Properties.

## Limitations

- Games in **exclusive** fullscreen can't be moved reliably — use borderless/windowed fullscreen.
- Two monitors of the *same model* share the same id; the first one found is used.
- Minimized windows are left to Windows.

## License

MIT
