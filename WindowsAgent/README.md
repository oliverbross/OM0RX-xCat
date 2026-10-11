# OM0RX Remote Station Agent for Windows

This directory is the independently deployable Windows controller shipped as
source with OM0RX-xCat. It owns the FLEX-8400 TCP connection and the KPA500 and
KAT500 serial ports; the macOS application connects over authenticated HTTPS
and WebSocket through private Tailscale Serve.

The agent requires Python 3.11 or newer. From this directory in PowerShell:

```powershell
.\scripts\setup_remote_agent.ps1
.\scripts\init_remote_agent.ps1 -Python .\.venv\Scripts\python.exe
.\.venv\Scripts\python.exe -m remote_station check
```

Continue with [the deployment and commissioning guide](docs/REMOTE_STATION_AGENT.md).
The protocol is documented in [REMOTE_STATION_PROTOCOL_V1.md](docs/REMOTE_STATION_PROTOCOL_V1.md).

No signed Windows `.exe` or MSI is currently produced or published. The
macOS release ZIP does not include this source directory.

Copyright © 2026 Oliver Bross OM0RX. GPL-3.0-only.
