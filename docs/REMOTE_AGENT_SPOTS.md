# RUMlogNG to FLEX spot bridge

OM0RX-xCat 0.4 receives RUMlogNG's N1MM-compatible `<spot>` UDP messages on
loopback and forwards panadapter markers through the authenticated Remote
Station Agent. It does not expose FLEX TCP port 4992 to the Internet and it
does not send CAT, PTT, TUNE, CWX, frequency, mode, antenna, or RF-power writes.

## Mac configuration

- RUMlogNG Settings → UDP → **DX spot (N1MM)**: enabled
- Host: `127.0.0.1`
- Logbook UDP port: `12062`
- OM0RX-xCat contest UDP port: `12063`
- OM0RX-xCat Spots → **Enable**: enabled

Logbook rules match Station worked before, DXCC/Band/Mode/Slot not confirmed,
and Other. Contest rules match New multiplier, Worked before, Useful, Useless,
and Unknown. Each rule has an editable FLEX priority from 1 through 5, RGB
colour, and marker lifetime.

## Agent protocol

The agent advertises `add_spot` in `state.capabilities.commands` and accepts it
through the existing authenticated `POST /api/v1/commands` envelope. Arguments:

```json
{
  "frequency_hz": 14074000,
  "callsign": "K1ABC",
  "mode": "DIGU",
  "source": "RUMlogNG Logbook",
  "spotter": "OM0RX",
  "comment": "DX",
  "timestamp": 1791628830,
  "lifetime_seconds": 900,
  "priority": 4,
  "color": "#30D158"
}
```

`add_spot` is a display-only operation. It bypasses neither authentication nor
input validation, but it does not require station commissioning because it
cannot change RF state. The Windows runtime maps the request to the existing
`FlexCtl.add_spot` SmartSDR command path.

## Windows handoff

Fetch branch `codex/remote-agent-flex-spots` from
`https://github.com/oliverbross/om0rx-radio-control.git`, verify the pushed SHA
reported by the Mac task, run
`uv run --extra dev pytest -q tests/smoke/test_remote_station_agent.py`, then
restart the Remote Station Agent. Confirm `/api/v1/state` advertises
`add_spot`. Do not paste or log the bearer token.

After the Mac application is running, a RUMlog DX spot should increment the
Received and Forwarded counters and appear on the FLEX panadapter. This
acceptance is receive/display-only and must not include an RF transmission.

## Station configuration from the Mac

OM0RX-xCat's **Station** tab loads the Windows agent's complete public
configuration over authenticated HTTPS. It exposes the KPA500 and KAT500
enable/port/baud settings, FLEX station and antenna policy, tune limits,
commissioning flag, KAT antenna names, and the per-band PA, barefoot, digital
PA, drive-power, FLEX TX, and KAT-output matrix.

**Save to Windows** sends the complete public configuration to authenticated
`PUT /api/v1/config`. The agent validates the document, preserves its server
bind settings and bearer token, and writes the file atomically. A successful
save requires a controlled Windows agent restart before the new configuration
is active. Saving settings does not itself send a station-control command or
transmit RF.

## macOS verification — 2026-10-10

- The Windows `codex/remote-agent-flex-spots` history through reported tip
  `4bf518f1971a740b236f0a062c1412021018fbe1` was fetched and preserved by a
  normal merge. No Windows work was reset or overwritten.
- The installed `/Applications/OM0RX-xCat.app` is source build 0.4.0 (6), is
  validly Developer ID signed, and reconnects to the authenticated HTTPS and
  WebSocket agent.
- Live readback showed FLEX VFO A on approximately 21.049 MHz CW, KPA500 in
  standby, KAT500 on ANT1, a confirmed 15m route, and no active alarm.
- The Station tab loaded the complete Windows configuration and renders FLEX,
  KPA/KAT, tune, antenna-name, and all 11 per-band routing/drive rows on one
  screen without a page scrollbar.
- The live station monitor was verified both in the menu-bar panel and as the
  separate movable, always-on-top **OM0RX Station Monitor** window. The window
  shares the active xCat model and remembers its last screen position.
- RUMlog delivered a real `DL7PIA` 10.116 MHz spot to xCat. This exposed a
  Windows driver defect: it sent six-digit RGB although the SmartSDR Spot API
  requires ARGB, and it reported success without matching the radio response.
  The shared Windows branch now converts RGB to opaque ARGB and requires the
  matching zero-success acknowledgement.
- The complete Swift suite passed: 35 tests, 0 failures, across 7 suites.
- Final Maestro display acceptance remains pending only on deployment and a
  controlled restart of the updated Windows agent. No RF transmission was
  used during this verification.
