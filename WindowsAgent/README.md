# OM0RX Remote Station Agent for Windows

This directory is the independently deployable Windows controller shipped as
source with OM0RX-xCat. It owns the FLEX-8400 TCP connection and the KPA500 and
KAT500 serial ports; the macOS application connects over authenticated HTTPS
and WebSocket through private Tailscale Serve.

## What is included

| Component | Purpose |
| --- | --- |
| Controller | The single process that owns FLEX TCP and KPA500/KAT500 serial connections and exposes the authenticated API. |
| Tray controller | Shows sanitized live status and provides settings, widget, log, start, stop, and confirmed restart actions. |
| Settings application | Edits and validates every supported connection and station-policy setting without requiring PowerShell or direct JSON editing. |
| Station widget | A compact movable monitor for frequency, VFOs, RX/TX, RF drive, output power, SWR, amplifier/tuner telemetry, route, and alarms. |
| Startup scripts | Install separate controller and interactive tray scheduled tasks, plus an **OM0RX Remote Station Agent** Start menu shortcut. |
| Tailscale helper | Publishes the loopback-only service privately with Tailscale Serve; public Funnel exposure is not used. |

The tray, settings, and widget open as ordinary Windows GUI applications with
the PowerShell console hidden. The widget uses an `XX.XXX.XXX MHz` frequency
display, colour-coded state, and an **Open configuration** button. It remembers
its size and screen position and can be reopened from the tray at any time.

The tray and widget are user interfaces for the same controller, not additional
radio-control processes. The Start menu shortcut reuses the running tray and
does not create a duplicate agent instance.

## Install

The agent requires Python 3.11 or newer. From this directory in PowerShell:

```powershell
.\scripts\setup_remote_agent.ps1
.\scripts\init_remote_agent.ps1 -Python .\.venv\Scripts\python.exe
.\.venv\Scripts\python.exe -m remote_station check
```

After reviewing the generated configuration and completing a receive-only
validation, install the hidden controller and the interactive tray at login:

```powershell
.\scripts\install_remote_agent_startup.ps1 -Python .\.venv\Scripts\python.exe
.\scripts\install_remote_agent_tray_startup.ps1 -Python .\.venv\Scripts\python.exe
```

The second command creates the Start menu shortcut and starts the tray and
widget. Use the tray menu for routine start, stop, restart, settings, status,
and log access.

## Configuration and safety

The Settings window covers the loopback API, masked credential, FLEX address
and SmartSDR station, KPA/KAT ports, per-band antenna and tuner routes, PA
eligibility, PA and barefoot drive limits, digital-mode policy, tune limits,
and commissioning. A save creates a backup and atomically replaces the active
configuration only after the Python agent validates the complete profile.

The bearer token is masked and is never included in status text, URLs, logs,
or screenshots. The API listens on loopback and should be published only with
private Tailscale Serve. Do not use Tailscale Funnel or public router port
forwarding.

Transmit and route-changing commands remain guarded by the station coordinator.
The agent starts with a receive/MOX-off, amplifier-standby recovery check and
fails closed if fresh hardware state cannot be proven. Commission only after
the physical route, antenna matrix, key-interrupt path, and drive table have
been verified.

## Maintenance and tests

Run the complete Windows Agent tests from this directory with:

```powershell
.\scripts\setup_remote_agent.ps1 -Dev
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m ruff check .
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\remote_agent_settings.ps1 -SmokeTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\remote_agent_widget.ps1 -SmokeTest
```

Remove the startup integrations without deleting configuration or logs:

```powershell
.\scripts\uninstall_remote_agent_tray_startup.ps1
.\scripts\uninstall_remote_agent_startup.ps1
```

Continue with [the deployment and commissioning guide](docs/REMOTE_STATION_AGENT.md).
The protocol is documented in [REMOTE_STATION_PROTOCOL_V1.md](docs/REMOTE_STATION_PROTOCOL_V1.md).

The main [OM0RX-xCat README](../README.md) includes a screenshot of the macOS
client connected to this agent. A current Windows UI screenshot is intentionally
not bundled here until it can be captured from the verified build without
including station credentials or unrelated desktop content.

No signed Windows `.exe` or MSI is currently produced or published. The
macOS release ZIP does not include this source directory.

Copyright © 2026 Oliver Bross OM0RX. GPL-3.0-only.
